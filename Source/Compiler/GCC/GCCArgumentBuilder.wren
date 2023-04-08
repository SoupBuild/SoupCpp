﻿// <copyright file="GCCArgumentBuilder.wren" company="Soup">
// Copyright (c) Soup. All rights reserved.
// </copyright>

import "Soup.Cpp.Compiler:./CompileArguments" for LanguageStandard, OptimizationLevel
import "Soup.Cpp.Compiler:./LinkArguments" for LinkTarget

/// <summary>
/// A helper class that builds the correct set of compiler arguments for a given
/// set of options.
/// </summary>
class GCCArgumentBuilder {
	static Compiler_ArgumentFlag_GenerateDebugInformation { "g" }
	static Compiler_ArgumentFlag_CompileOnly { "c" }
	static Compiler_ArgumentFlag_IgnoreStandardIncludePaths { "X" }
	static Compiler_ArgumentFlag_Optimization_Disable { "O0" }
	static Compiler_ArgumentFlag_Optimization_Speed { "O3" }
	static Compiler_ArgumentFlag_Optimization_Size { "Os" }
	static Compiler_ArgumentParameter_Standard { "std" }
	static Compiler_ArgumentParameter_Output { "o" }
	static Compiler_ArgumentParameter_Include { "I" }
	static Compiler_ArgumentParameter_PreprocessorDefine { "D" }

	static Linker_ArgumentFlag_DLL { "dll" }
	static Linker_ArgumentFlag_Verbose { "v" }
	static Linker_ArgumentParameter_Output { "out" }
	static Linker_ArgumentParameter_ImplementationLibrary { "implib" }
	static Linker_ArgumentParameter_LibraryPath { "libpath" }
	static Linker_ArgumentParameter_Machine { "machine" }
	static Linker_ArgumentParameter_DefaultLibrary { "defaultlib" }
	static Linker_ArgumentValue_X64 { "X64" }
	static Linker_ArgumentValue_X86 { "X86" }

	static BuildSharedCompilerArguments(arguments) {
		// Calculate object output file
		var commandArguments = []

		// Generate source debug information
		if (arguments.GenerateSourceDebugInfo) {
			GCCArgumentBuilder.AddFlag(commandArguments, GCCArgumentBuilder.Compiler_ArgumentFlag_GenerateDebugInformation)
		}

		// Disabled individual warnings
		if (arguments.EnableWarningsAsErrors) {
			GCCArgumentBuilder.AddFlag(commandArguments, "Werror")
		}

		GCCArgumentBuilder.AddFlag(commandArguments, "W4")

		// Disable any requested warnings
		for (warning in arguments.DisabledWarnings) {
			GCCArgumentBuilder.AddFlagValue(commandArguments, "wd", warning)
		}

		// Enable any requested warnings
		for (warning in arguments.EnabledWarnings) {
			GCCArgumentBuilder.AddFlagValue(commandArguments, "w", warning)
		}

		// Set the language standard
		if (arguments.Standard == LanguageStandard.CPP11) {
			GCCArgumentBuilder.AddParameter(commandArguments, GCCArgumentBuilder.Compiler_ArgumentParameter_Standard, "c++11")
		} else if (arguments.Standard == LanguageStandard.CPP14) {
			GCCArgumentBuilder.AddParameter(commandArguments, GCCArgumentBuilder.Compiler_ArgumentParameter_Standard, "c++14")
		} else if (arguments.Standard == LanguageStandard.CPP17) {
			GCCArgumentBuilder.AddParameter(commandArguments, GCCArgumentBuilder.Compiler_ArgumentParameter_Standard, "c++17")
		} else if (arguments.Standard == LanguageStandard.CPP20) {
			GCCArgumentBuilder.AddParameter(commandArguments, GCCArgumentBuilder.Compiler_ArgumentParameter_Standard, "c++latest")
		} else {
			Fiber.abort("Unknown language standard %(arguments.Standard).")
		}

		// Set the optimization level
		if (arguments.Optimize == OptimizationLevel.None) {
			GCCArgumentBuilder.AddFlag(commandArguments, GCCArgumentBuilder.Compiler_ArgumentFlag_Optimization_Disable)
		} else if (arguments.Optimize == OptimizationLevel.Speed) {
			GCCArgumentBuilder.AddFlag(commandArguments, GCCArgumentBuilder.Compiler_ArgumentFlag_Optimization_Speed)
		} else if (arguments.Optimize == OptimizationLevel.Size) {
			GCCArgumentBuilder.AddFlag(commandArguments, GCCArgumentBuilder.Compiler_ArgumentFlag_Optimization_Size)
		} else {
			Fiber.abort("Unknown optimization level %(arguments.Optimize)")
		}

		// Set the include paths
		for (directory in arguments.IncludeDirectories) {
			GCCArgumentBuilder.AddFlagValueWithQuotes(commandArguments, GCCArgumentBuilder.Compiler_ArgumentParameter_Include, directory.toString)
		}

		// Set the preprocessor definitions
		for (definition in arguments.PreprocessorDefinitions) {
			GCCArgumentBuilder.AddFlagValue(commandArguments, GCCArgumentBuilder.Compiler_ArgumentParameter_PreprocessorDefine, definition)
		}

		// Ignore Standard Include Paths to prevent pulling in accidental headers
		GCCArgumentBuilder.AddFlag(commandArguments, GCCArgumentBuilder.Compiler_ArgumentFlag_IgnoreStandardIncludePaths)

		// Enable c++ exceptions
		GCCArgumentBuilder.AddFlag(commandArguments, "fexceptions")

		// Add the module references as input
		for (moduleFile in arguments.IncludeModules) {
			GCCArgumentBuilder.AddFlag(commandArguments, "reference")
			GCCArgumentBuilder.AddValueWithQuotes(commandArguments, moduleFile.toString)
		}

		// Only run preprocessor, compile and assemble
		GCCArgumentBuilder.AddFlag(commandArguments, GCCArgumentBuilder.Compiler_ArgumentFlag_CompileOnly)

		return commandArguments
	}

	static BuildResourceCompilerArguments(
		targetRootDirectory,
		arguments) {
		if (arguments.ResourceFile == null) {
			Fiber.abort("Argument null")
		}

		// Build the arguments for a standard translation unit
		var commandArguments = []

		// TODO: Defines?
		GCCArgumentBuilder.AddFlagValue(commandArguments, GCCArgumentBuilder.Compiler_ArgumentParameter_PreprocessorDefine, "_UNICODE")
		GCCArgumentBuilder.AddFlagValue(commandArguments, GCCArgumentBuilder.Compiler_ArgumentParameter_PreprocessorDefine, "UNICODE")

		// Specify default language using language identifier
		GCCArgumentBuilder.AddFlagValueWithQuotes(commandArguments, "l", "0x0409")

		// Set the include paths
		for (directory in arguments.IncludeDirectories) {
			GCCArgumentBuilder.AddFlagValueWithQuotes(commandArguments, GCCArgumentBuilder.Compiler_ArgumentParameter_Include, directory.toString)
		}

		// Add the target file as outputs
		var absoluteTargetFile = targetRootDirectory + arguments.ResourceFile.TargetFile
		GCCArgumentBuilder.AddFlagValueWithQuotes(
			commandArguments,
			GCCArgumentBuilder.Compiler_ArgumentParameter_Output,
			absoluteTargetFile.toString)

		// Add the source file as input
		commandArguments.add(arguments.ResourceFile.SourceFile.toString)

		return commandArguments
	}

	static BuildInterfaceUnitCompilerArguments(
		targetRootDirectory,
		arguments,
		responseFile) {
		// Build the arguments for a standard translation unit
		var commandArguments = []

		// Add the response file
		commandArguments.add("@" + responseFile.toString)

		// Add the module references as input
		for (moduleFile in arguments.IncludeModules) {
			GCCArgumentBuilder.AddFlag(commandArguments, "reference")
			GCCArgumentBuilder.AddValueWithQuotes(commandArguments, moduleFile.toString)
		}

		// Add the source file as input
		commandArguments.add(arguments.SourceFile.toString)

		// Add the target file as outputs
		var absoluteTargetFile = targetRootDirectory + arguments.TargetFile
		GCCArgumentBuilder.AddFlagValueWithQuotes(
			commandArguments,
			GCCArgumentBuilder.Compiler_ArgumentParameter_Output,
			absoluteTargetFile.toString)

		// Add the unique arguments for an interface unit
		GCCArgumentBuilder.AddFlag(commandArguments, "interface")

		// Specify the module interface file output
		GCCArgumentBuilder.AddFlag(commandArguments, "ifcOutput")

		var absoluteModuleInterfaceFile = targetRootDirectory + arguments.ModuleInterfaceTarget
		GCCArgumentBuilder.AddValueWithQuotes(commandArguments, absoluteModuleInterfaceFile.toString)

		return commandArguments
	}

	static BuildAssemblyUnitCompilerArguments(
		targetRootDirectory,
		sharedArguments,
		arguments) {
		// Build the arguments for a standard translation unit
		var commandArguments = []

		// Add the target file as outputs
		var absoluteTargetFile = targetRootDirectory + arguments.TargetFile
		GCCArgumentBuilder.AddFlagValueWithQuotes(
			commandArguments,
			GCCArgumentBuilder.Compiler_ArgumentParameter_Output,
			absoluteTargetFile.toString)

		// Only run preprocessor, compile and assemble
		GCCArgumentBuilder.AddFlag(commandArguments, GCCArgumentBuilder.Compiler_ArgumentFlag_CompileOnly)

		// Generate debug information
		GCCArgumentBuilder.AddFlag(commandArguments, GCCArgumentBuilder.Compiler_ArgumentFlag_GenerateDebugInformation)

		// Enable warnings
		GCCArgumentBuilder.AddFlag(commandArguments, "W3")

		// Set the include paths
		for (directory in sharedArguments.IncludeDirectories) {
			GCCArgumentBuilder.AddFlagValueWithQuotes(commandArguments, GCCArgumentBuilder.Compiler_ArgumentParameter_Include, directory.toString)
		}

		// Add the source file as input
		commandArguments.add(arguments.SourceFile.toString)

		return commandArguments
	}
	
	static BuildPartitionUnitCompilerArguments(
		targetRootDirectory,
		arguments,
		responseFile) {
		// Build the arguments for a standard translation unit
		var commandArguments = []

		// Add the response file
		commandArguments.add("@" + responseFile.toString)

		// Add the module references as input
		for (moduleFile in arguments.IncludeModules) {
			GCCArgumentBuilder.AddFlag(commandArguments, "reference")
			GCCArgumentBuilder.AddValueWithQuotes(commandArguments, moduleFile.toString)
		}

		// Add the source file as input
		commandArguments.add(arguments.SourceFile.toString)

		// Add the target file as outputs
		var absoluteTargetFile = targetRootDirectory + arguments.TargetFile
		GCCArgumentBuilder.AddFlagValueWithQuotes(
			commandArguments,
			GCCArgumentBuilder.Compiler_ArgumentParameter_Output,
			absoluteTargetFile.toString)

		// Add the unique arguments for an partition unit
		GCCArgumentBuilder.AddFlag(commandArguments, "interface")

		// Specify the module interface file output
		GCCArgumentBuilder.AddFlag(commandArguments, "ifcOutput")

		var absoluteModuleInterfaceFile = targetRootDirectory + arguments.ModuleInterfaceTarget
		GCCArgumentBuilder.AddValueWithQuotes(commandArguments, absoluteModuleInterfaceFile.toString)

		return commandArguments
	}

	static BuildTranslationUnitCompilerArguments(
		targetRootDirectory,
		arguments,
		responseFile,
		internalModules) {
		// Calculate object output file
		var commandArguments = []

		// Add the response file
		commandArguments.add("@" + responseFile.toString)

		// Add the internal module references as input
		for (moduleFile in arguments.IncludeModules) {
			GCCArgumentBuilder.AddFlag(commandArguments, "reference")
			GCCArgumentBuilder.AddValueWithQuotes(commandArguments, moduleFile.toString)
		}

		// Add the internal module references as input
		for (moduleFile in internalModules) {
			GCCArgumentBuilder.AddFlag(commandArguments, "reference")
			GCCArgumentBuilder.AddValueWithQuotes(commandArguments, moduleFile.toString)
		}

		// Add the source file as input
		commandArguments.add(arguments.SourceFile.toString)

		// Add the target file as outputs
		var absoluteTargetFile = targetRootDirectory + arguments.TargetFile
		GCCArgumentBuilder.AddFlagValueWithQuotes(
			commandArguments,
			GCCArgumentBuilder.Compiler_ArgumentParameter_Output,
			absoluteTargetFile.toString)

		return commandArguments
	}

	static BuildLinkerArguments(arguments) {
		// Verify the input
		if (arguments.TargetFile.GetFileName() == null) {
			Fiber.abort("Target file cannot be empty.")
		}

		var commandArguments = []

		// Disable incremental linking. I believe this is causing issues as the linker reads and writes to the same file
		GCCArgumentBuilder.AddParameter(commandArguments, "INCREMENTAL", "NO")

		// Disable the default libraries, we will set this up
		// GCCArgumentBuilder.AddFlag(commandArguments, GCCArgumentBuilder.Linker_ArgumentFlag_NoDefaultLibraries)

		// Enable verbose output
		// GCCArgumentBuilder.AddFlag(commandArguments, GCCArgumentBuilder.Linker_ArgumentFlag_Verbose)

		// Generate source debug information
		if (arguments.GenerateSourceDebugInfo) {
			GCCArgumentBuilder.AddParameter(commandArguments, "debug", "full")
		}

		// Calculate object output file
		if (arguments.TargetType == LinkTarget.StaticLibrary) {
			// Nothing to do
		} else if (arguments.TargetType == LinkTarget.DynamicLibrary) {
			// TODO: May want to specify the exact value
			// set the default lib to mutlithreaded
			// GCCArgumentBuilder.AddParameter(commandArguments, "defaultlib", "libcmt")
			GCCArgumentBuilder.AddParameter(commandArguments, "subsystem", "console")

			// Create a dynamic library
			GCCArgumentBuilder.AddFlag(commandArguments, GCCArgumentBuilder.Linker_ArgumentFlag_DLL)

			// Set the output implementation library
			GCCArgumentBuilder.AddParameterWithQuotes(
				commandArguments,
				GCCArgumentBuilder.Linker_ArgumentParameter_ImplementationLibrary,
				arguments.ImplementationFile.toString)
		} else if (arguments.TargetType == LinkTarget.Executable) {
			// TODO: May want to specify the exact value
			// set the default lib to multithreaded
			// GCCArgumentBuilder.AddParameter(commandArguments, "defaultlib", "libcmt")
			GCCArgumentBuilder.AddParameter(commandArguments, "subsystem", "console")
		} else if (arguments.TargetType == LinkTarget.WindowsApplication) {
			// TODO: May want to specify the exact value
			// set the default lib to multithreaded
			// GCCArgumentBuilder.AddParameter(commandArguments, "defaultlib", "libcmt")
			GCCArgumentBuilder.AddParameter(commandArguments, "subsystem", "windows")
		} else {
			Fiber.abort("Unknown LinkTarget.")
		}

		// Add the machine target
		if (arguments.TargetArchitecture == "x64") {
			GCCArgumentBuilder.AddParameter(commandArguments, GCCArgumentBuilder.Linker_ArgumentParameter_Machine, GCCArgumentBuilder.Linker_ArgumentValue_X64)
		} else if (arguments.TargetArchitecture == "x86") {
			GCCArgumentBuilder.AddParameter(commandArguments, GCCArgumentBuilder.Linker_ArgumentParameter_Machine, GCCArgumentBuilder.Linker_ArgumentValue_X86)
		} else {
			Fiber.abort("Unknown target architecture.")
		}

		// Set the library paths
		for (directory in arguments.LibraryPaths) {
			GCCArgumentBuilder.AddParameterWithQuotes(commandArguments, GCCArgumentBuilder.Linker_ArgumentParameter_LibraryPath, directory.toString)
		}

		// Add the target as an output
		GCCArgumentBuilder.AddParameterWithQuotes(commandArguments, GCCArgumentBuilder.Linker_ArgumentParameter_Output, arguments.TargetFile.toString)

		// Add the library files
		for (file in arguments.LibraryFiles) {
			// Add the library files as input
			commandArguments.add(file.toString)
		}

		// Add the external libraries as default libraries so they are resolved last
		for (file in arguments.ExternalLibraryFiles) {
			// Add the external library files as input
			// TODO: Explicitly ignore these files from the input for now
			GCCArgumentBuilder.AddParameter(commandArguments, GCCArgumentBuilder.Linker_ArgumentParameter_DefaultLibrary, file.toString)
		}

		// Add the object files
		for (file in arguments.ObjectFiles) {
			// Add the object files as input
			commandArguments.add(file.toString)
		}

		return commandArguments
	}

	static AddValueWithQuotes(arguments, value) {
		arguments.add("\"%(value)\"")
	}

	static AddFlag(arguments, flag) {
		arguments.add("-%(flag)")
	}

	static AddFlagValue(arguments, flag, value) {
		arguments.add("-%(flag)%(value)")
	}

	static AddFlagValueWithQuotes(arguments, flag, value) {
		arguments.add("-%(flag)\"%(value)\"")
	}

	static AddParameter(arguments, name, value) {
		arguments.add("-%(name):%(value)")
	}

	static AddParameterWithQuotes(arguments, name, value) {
		arguments.add("-%(name):\"%(value)\"")
	}
}