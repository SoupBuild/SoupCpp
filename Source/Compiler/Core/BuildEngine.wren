﻿// <copyright file="BuildEngine.wren" company="Soup">
// Copyright (c) Soup. All rights reserved.
// </copyright>

import "./BuildResult" for BuildResult
import "./BuildArguments" for BuildOptimizationLevel, BuildTargetType
import "./LinkArguments" for LinkArguments, LinkTarget
import "./CompileArguments" for InterfaceUnitCompileArguments, OptimizationLevel, ResourceCompileArguments, SharedCompileArguments, TranslationUnitCompileArguments
import "../../IBuildState" for TraceLevel
import "../../SharedOperations" for SharedOperations
import "../../Utils/Path" for Path
import "../../Utils/Set" for Set

/// <summary>
/// The build engine
/// </summary>
class BuildEngine {
	construct new(compiler) {
		_compiler = compiler
	}

	/// <summary>
	/// Generate the required build operations for the requested build
	/// </summary>
	Execute(buildState, arguments) {
		var result = BuildResult.new()

		// All dependencies must include the entire interface dependency closure
		result.ModuleDependencies = []
		result.ModuleDependencies = result.ModuleDependencies + arguments.ModuleDependencies

		// Ensure the output directories exists as the first step
		result.BuildOperations.add(
			SharedOperations.CreateCreateDirectoryOperation(
				arguments.TargetRootDirectory,
				arguments.ObjectDirectory))
		result.BuildOperations.add(
			SharedOperations.CreateCreateDirectoryOperation(
				arguments.TargetRootDirectory,
				arguments.BinaryDirectory))

		// Perform the core compilation of the source files
		this.CoreCompile(buildState, arguments, result)

		// Link the final target after all of the compile graph is done
		this.CoreLink(buildState, arguments, result)

		// Copy previous runtime dependencies after linking has completed
		this.CopyRuntimeDependencies(arguments, result)

		return result
	}

	/// <summary>
	/// Compile the module and source files
	/// </summary>
	CoreCompile(buildState, arguments, result) {
		// Ensure there are actually files to build
		if (arguments.ModuleInterfacePartitionSourceFiles.count != 0 ||
			!(arguments.ModuleInterfaceSourceFile is Null) ||
			arguments.SourceFiles.count != 0 ||
			arguments.AssemblySourceFiles.count != 0) {
			// Setup the shared properties
			var compileArguments = SharedCompileArguments.new()
			compileArguments.Standard = arguments.LanguageStandard
			compileArguments.Optimize = this.ConvertBuildOptimizationLevel(arguments.OptimizationLevel)
			compileArguments.SourceRootDirectory = arguments.SourceRootDirectory
			compileArguments.TargetRootDirectory = arguments.TargetRootDirectory
			compileArguments.ObjectDirectory = arguments.ObjectDirectory
			compileArguments.IncludeDirectories = arguments.IncludeDirectories
			compileArguments.IncludeModules = arguments.ModuleDependencies
			compileArguments.PreprocessorDefinitions = arguments.PreprocessorDefinitions
			compileArguments.GenerateSourceDebugInfo = arguments.GenerateSourceDebugInfo
			compileArguments.EnableWarningsAsErrors = arguments.EnableWarningsAsErrors
			compileArguments.DisabledWarnings = arguments.DisabledWarnings
			compileArguments.EnabledWarnings = arguments.EnabledWarnings
			compileArguments.CustomProperties = arguments.CustomProperties

			// Compile the resource file if present
			if (arguments.ResourceFile) {
				buildState.LogTrace(TraceLevel.Information, "Generate Resource File Compile: %(arguments.ResourceFile)")

				var compiledResourceFile =
					arguments.ObjectDirectory +
					Path.new(arguments.ResourceFile.GetFileName())
				compiledResourceFile.SetFileExtension(_compiler.ResourceFileExtension)

				var compileResourceFileArguments = ResourceCompileArguments.new()
				compileResourceFileArguments.SourceFile = arguments.ResourceFile
				compileResourceFileArguments.TargetFile = compiledResourceFile

				// Add the resource file arguments to the shared build definition
				compileArguments.ResourceFile = compileResourceFileArguments
			}

			// Build up the entire Interface Dependency Closure for each file
			var partitionInterfaceDependencyLookup = {}
			for (file in arguments.ModuleInterfacePartitionSourceFiles) {
				partitionInterfaceDependencyLookup[file.File.toString] = file.Imports
			}

			// Compile the individual module interface partition translation units
			var compileInterfacePartitionUnits = []
			var allPartitionInterfaces = []
			for (file in arguments.ModuleInterfacePartitionSourceFiles) {
				buildState.LogTrace(TraceLevel.Information, "Generate Module Interface Partition Compile Operation: %(file.File)")

				var objectModuleInterfaceFile =
					arguments.ObjectDirectory +
					Path.new(file.File.GetFileName())
				objectModuleInterfaceFile.SetFileExtension(_compiler.ModuleFileExtension)

				var interfaceDependencyClosure = Set.new()
				this.BuildClosure(interfaceDependencyClosure, file.File, partitionInterfaceDependencyLookup)
				if (interfaceDependencyClosure.contains(file.File)) {
					Fiber.abort("Circular partition references in: %(file.File)")
				}

				var partitionImports = []
				for (dependency in interfaceDependencyClosure.list) {
					var importInterface = arguments.ObjectDirectory + Path.new(dependency.GetFileName())
					importInterface.SetFileExtension(_compiler.ModuleFileExtension)
					partitionImports.add(arguments.TargetRootDirectory + importInterface)
				}

				var compileFileArguments = InterfaceUnitCompileArguments.new()
				compileFileArguments.SourceFile = file.File
				compileFileArguments.TargetFile = arguments.ObjectDirectory + Path.new(file.File.GetFileName())
				compileFileArguments.IncludeModules = partitionImports
				compileFileArguments.ModuleInterfaceTarget = objectModuleInterfaceFile

				compileFileArguments.TargetFile.SetFileExtension(_compiler.ObjectFileExtension)

				compileInterfacePartitionUnits.add(compileFileArguments)
				allPartitionInterfaces.add(arguments.TargetRootDirectory + objectModuleInterfaceFile)
			}

			// Add all partition unit interface files as module dependencies since MSVC does not
			// combine the interfaces into the final interface unit
			for (module in allPartitionInterfaces) {
				result.ModuleDependencies.add(module)
			}

			compileArguments.InterfacePartitionUnits = compileInterfacePartitionUnits

			// Compile the module interface unit if present
			if (!(arguments.ModuleInterfaceSourceFile is Null)) {
				buildState.LogTrace(TraceLevel.Information, "Generate Module Interface Unit Compile: %(arguments.ModuleInterfaceSourceFile)")

				var objectModuleInterfaceFile =
					arguments.ObjectDirectory +
					Path.new(arguments.ModuleInterfaceSourceFile.GetFileName())
				objectModuleInterfaceFile.SetFileExtension(_compiler.ModuleFileExtension)
				var binaryOutputModuleInterfaceFile =
					arguments.BinaryDirectory +
					Path.new(arguments.TargetName + "." + _compiler.ModuleFileExtension)

				var compileModuleFileArguments = InterfaceUnitCompileArguments.new()
				compileModuleFileArguments.SourceFile = arguments.ModuleInterfaceSourceFile
				compileModuleFileArguments.TargetFile = arguments.ObjectDirectory + Path.new(arguments.ModuleInterfaceSourceFile.GetFileName())
				compileModuleFileArguments.IncludeModules = allPartitionInterfaces
				compileModuleFileArguments.ModuleInterfaceTarget = objectModuleInterfaceFile

				compileModuleFileArguments.TargetFile.SetFileExtension(_compiler.ObjectFileExtension)

				// Add the interface unit arguments to the shared build definition
				compileArguments.InterfaceUnit = compileModuleFileArguments

				// Copy the binary module interface to the binary directory after compiling
				var copyInterfaceOperation =
					SharedOperations.CreateCopyFileOperation(
						arguments.TargetRootDirectory,
						objectModuleInterfaceFile,
						binaryOutputModuleInterfaceFile)
				result.BuildOperations.add(copyInterfaceOperation)

				// Add output module interface to the parent set of modules
				// This will allow the module implementation units access as well as downstream
				// dependencies to the public interface.
				result.ModuleDependencies.add(
					binaryOutputModuleInterfaceFile.HasRoot ?
						binaryOutputModuleInterfaceFile :
						arguments.TargetRootDirectory + binaryOutputModuleInterfaceFile)
			}

			// Compile the individual translation units
			var compileImplementationUnits = []
			for (file in arguments.SourceFiles) {
				buildState.LogTrace(TraceLevel.Information, "Generate Compile Operation: %(file)")

				var compileFileArguments = TranslationUnitCompileArguments.new()
				compileFileArguments.SourceFile = file
				compileFileArguments.TargetFile = arguments.ObjectDirectory + Path.new(file.GetFileName())
				compileFileArguments.TargetFile.SetFileExtension(_compiler.ObjectFileExtension)

				compileImplementationUnits.add(compileFileArguments)
			}

			compileArguments.ImplementationUnits = compileImplementationUnits

			// Compile the individual assembly units
			var compileAssemblyUnits = []
			for (file in arguments.AssemblySourceFiles) {
				buildState.LogTrace(TraceLevel.Information, "Generate Compile Assembly Operation: %(file)")

				var compileFileArguments = TranslationUnitCompileArguments.new()
				compileFileArguments.SourceFile = file
				compileFileArguments.TargetFile = arguments.ObjectDirectory + Path.new(file.GetFileName())
				compileFileArguments.TargetFile.SetFileExtension(_compiler.ObjectFileExtension)

				compileAssemblyUnits.add(compileFileArguments)
			}

			compileArguments.AssemblyUnits = compileAssemblyUnits

			// Compile all source files as a single call
			var compileOperations = _compiler.CreateCompileOperations(compileArguments)
			for (operation in compileOperations) {
				result.BuildOperations.add(operation)
			}
		}
	}

	/// <summary>
	/// Link the library
	/// </summary>
	CoreLink(
		buildState,
		arguments,
		result) {
		buildState.LogTrace(TraceLevel.Information, "CoreLink")

		var targetFile
		var implementationFile
		if (arguments.TargetType == BuildTargetType.StaticLibrary) {
			targetFile = arguments.BinaryDirectory +
				Path.new(arguments.TargetName + "." + _compiler.StaticLibraryFileExtension)
		} else if (arguments.TargetType == BuildTargetType.DynamicLibrary) {
			targetFile = arguments.BinaryDirectory +
				Path.new(arguments.TargetName + "." + _compiler.DynamicLibraryFileExtension)
			implementationFile = arguments.BinaryDirectory +
				Path.new(arguments.TargetName + "." + _compiler.StaticLibraryFileExtension)
		} else if (arguments.TargetType == BuildTargetType.Executable ||
			arguments.TargetType == BuildTargetType.WindowsApplication) {
			targetFile = arguments.BinaryDirectory + 
				Path.new(arguments.TargetName + ".exe")
		} else {
			Fiber.abort("Unknown build target type.")
		}

		buildState.LogTrace(TraceLevel.Information, "Linking target")

		var linkArguments = LinkArguments.new()
		linkArguments.TargetFile = targetFile
		linkArguments.TargetArchitecture = arguments.TargetArchitecture
		linkArguments.ImplementationFile = implementationFile
		linkArguments.TargetRootDirectory = arguments.TargetRootDirectory
		linkArguments.LibraryPaths = arguments.LibraryPaths
		linkArguments.GenerateSourceDebugInfo = arguments.GenerateSourceDebugInfo

		// Only resolve link libraries if not a library ourself
		if (arguments.TargetType != BuildTargetType.StaticLibrary) {
			linkArguments.ExternalLibraryFiles = arguments.PlatformLinkDependencies
			linkArguments.LibraryFiles = arguments.LinkDependencies
		}

		// Translate the target type into the link target
		// and determine what dependencies to inject into downstream builds

		if (arguments.TargetType == BuildTargetType.StaticLibrary) {
			linkArguments.TargetType = LinkTarget.StaticLibrary
			
			// Add the library as a link dependency and all recursive libraries
			result.LinkDependencies = [] + arguments.LinkDependencies
			var absoluteTargetFile = linkArguments.TargetFile.HasRoot ? linkArguments.TargetFile : linkArguments.TargetRootDirectory + linkArguments.TargetFile
			result.LinkDependencies.add(absoluteTargetFile)
		} else if (arguments.TargetType == BuildTargetType.DynamicLibrary) {
			linkArguments.TargetType = LinkTarget.DynamicLibrary

			// Add the DLL as a runtime dependency
			var absoluteTargetFile = linkArguments.TargetFile.HasRoot ? linkArguments.TargetFile : linkArguments.TargetRootDirectory + linkArguments.TargetFile
			result.RuntimeDependencies.add(absoluteTargetFile)

			// Clear out all previous link dependencies and replace with the 
			// single implementation library for the DLL
			var absoluteImplementationFile = linkArguments.ImplementationFile.HasRoot ? linkArguments.ImplementationFile : linkArguments.TargetRootDirectory + linkArguments.ImplementationFile
			result.LinkDependencies.add(absoluteImplementationFile)

			// Set the targe file
			result.TargetFile = absoluteTargetFile
		} else if (arguments.TargetType == BuildTargetType.Executable) {
			linkArguments.TargetType = LinkTarget.Executable

			// Add the Executable as a runtime dependency
			var absoluteTargetFile = linkArguments.TargetFile.HasRoot ? linkArguments.TargetFile : linkArguments.TargetRootDirectory + linkArguments.TargetFile
			result.RuntimeDependencies.add(absoluteTargetFile)

			// All link dependencies stop here.

			// Set the targe file
			result.TargetFile = absoluteTargetFile
		} else if (arguments.TargetType == BuildTargetType.WindowsApplication) {
			linkArguments.TargetType = LinkTarget.WindowsApplication

			// Add the Executable as a runtime dependency
			var absoluteTargetFile = linkArguments.TargetFile.HasRoot ? linkArguments.TargetFile : linkArguments.TargetRootDirectory + linkArguments.TargetFile
			result.RuntimeDependencies.add(absoluteTargetFile)

			// All link dependencies stop here.

			// Set the targe file
			result.TargetFile = absoluteTargetFile
		} else {
			Fiber.abort("Unknown build target type.")
		}

		// Build up the set of object files
		var objectFiles = []

		// Add the resource file if present
		if (!(arguments.ResourceFile is Null)) {
			var compiledResourceFile =
				arguments.ObjectDirectory +
				Path.new(arguments.ResourceFile.GetFileName())
			compiledResourceFile.SetFileExtension(_compiler.ResourceFileExtension)

			objectFiles.add(compiledResourceFile)
		}

		// Add the partition object files
		for (sourceFile in arguments.ModuleInterfacePartitionSourceFiles) {
			var objectFile = arguments.ObjectDirectory + Path.new(sourceFile.File.GetFileName())
			objectFile.SetFileExtension(_compiler.ObjectFileExtension)
			objectFiles.add(objectFile)
		}

		// Add the module interface object file if present
		if (!(arguments.ModuleInterfaceSourceFile is Null)) {
			var objectFile = arguments.ObjectDirectory + Path.new(arguments.ModuleInterfaceSourceFile.GetFileName())
			objectFile.SetFileExtension(_compiler.ObjectFileExtension)
			objectFiles.add(objectFile)
		}

		// Add the implementation unit object files
		for (sourceFile in arguments.SourceFiles) {
			var objectFile = arguments.ObjectDirectory + Path.new(sourceFile.GetFileName())
			objectFile.SetFileExtension(_compiler.ObjectFileExtension)
			objectFiles.add(objectFile)
		}

		// Add the assembly unit object files
		for (sourceFile in arguments.AssemblySourceFiles) {
			var objectFile = arguments.ObjectDirectory + Path.new(sourceFile.GetFileName())
			objectFile.SetFileExtension(_compiler.ObjectFileExtension)
			objectFiles.add(objectFile)
		}

		linkArguments.ObjectFiles = objectFiles

		// Perform the link
		buildState.LogTrace(TraceLevel.Information, "Generate Link Operation: %(linkArguments.TargetFile)")
		var linkOperation = _compiler.CreateLinkOperation(linkArguments)
		result.BuildOperations.add(linkOperation)

		// Pass along the link arguments for internal access
		result.InternalLinkDependencies = []
		result.InternalLinkDependencies = result.InternalLinkDependencies + arguments.LinkDependencies
		for (file in linkArguments.ObjectFiles) {
			result.InternalLinkDependencies.add(file)
		}
	}

	/// <summary>
	/// Copy runtime dependencies
	/// </summary>
	CopyRuntimeDependencies(arguments, result) {
		if (arguments.TargetType == BuildTargetType.Executable ||
			arguments.TargetType == BuildTargetType.WindowsApplication ||
			arguments.TargetType == BuildTargetType.DynamicLibrary) {
			for (source in arguments.RuntimeDependencies) {
				var target = arguments.BinaryDirectory + Path.new(source.GetFileName())
				var operation = SharedOperations.CreateCopyFileOperation(
					arguments.TargetRootDirectory,
					source,
					target)
				result.BuildOperations.add(operation)

				// Add the copied file as the new runtime dependency
				result.RuntimeDependencies.add(target)
			}
		} else {
			// Pass along all runtime dependencies in their original location
			for (source in arguments.RuntimeDependencies) {
				result.RuntimeDependencies.add(source)
			}
		}
	}

	BuildClosure(closure, file, partitionInterfaceDependencyLookup) {
		for (childFile in partitionInterfaceDependencyLookup[file.toString]) {
			closure.add(childFile)
			this.BuildClosure(closure, childFile, partitionInterfaceDependencyLookup)
		}
	}

	ConvertBuildOptimizationLevel(value) {
		if (value == BuildOptimizationLevel.None) {
			return OptimizationLevel.None
		} else if (value == BuildOptimizationLevel.Speed) {
			return OptimizationLevel.Speed
		} else if (value == BuildOptimizationLevel.Size) {
			return OptimizationLevel.Size
		} else {
			Fiber.abort("Unknown BuildOptimizationLevel.")
		}
	}
}