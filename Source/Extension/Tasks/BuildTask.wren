﻿// <copyright file="BuildTask.cs" company="Soup">
// Copyright (c) Soup. All rights reserved.
// </copyright>

using Opal;
using Opal.System;
using Soup.Build.Cpp.Compiler;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Soup.Build.Cpp
{
	public class BuildTask : IBuildTask
	{
		private IBuildState buildState;
		private IValueFactory factory;
		private IDictionary<string, Func<IValueTable, ICompiler>> compilerFactory;

		/// <summary>
		/// Get the run before list
		/// </summary>
		public static IReadOnlyList<string> RunBeforeList => new List<string>()
		{
		};

		/// <summary>
		/// Get the run after list
		/// </summary>
		public static IReadOnlyList<string> RunAfterList => new List<string>()
		{
		};

		public BuildTask(IBuildState buildState, IValueFactory factory) :
			this(buildState, factory, new Dictionary<string, Func<IValueTable, ICompiler>>())
		{
			// Register default compilers
			this.compilerFactory.Add("MSVC", (IValueTable activeState) =>
			{
				var clToolPath = new Path(activeState["MSVC.ClToolPath"].AsString());
				var linkToolPath = new Path(activeState["MSVC.LinkToolPath"].AsString());
				var libToolPath = new Path(activeState["MSVC.LibToolPath"].AsString());
				var rcToolPath = new Path(activeState["MSVC.RCToolPath"].AsString());
				var mlToolPath = new Path(activeState["MSVC.MLToolPath"].AsString());
				return new Compiler.MSVC.Compiler(
					clToolPath,
					linkToolPath,
					libToolPath,
					rcToolPath,
					mlToolPath);
			});
		}

		public BuildTask(IBuildState buildState, IValueFactory factory, Dictionary<string, Func<IValueTable, ICompiler>> compilerFactory)
		{
			this.buildState = buildState;
			this.factory = factory;
			this.compilerFactory = compilerFactory;

			// TODO: Not ideal to be registering this on the fly...
			if (!LifetimeManager.Has<IProcessManager>())
			{
				LifetimeManager.RegisterSingleton<IProcessManager, RuntimeProcessManager>();
			}
		}

		public void Execute()
		{
			var activeState = this.buildState.ActiveState;
			var sharedState = this.buildState.SharedState;

			var buildTable = activeState["Build"].AsTable();
			var parametersTable = activeState["Parameters"].AsTable();

			var arguments = new BuildArguments();
			arguments.TargetArchitecture = parametersTable["Architecture"].AsString();
			arguments.TargetName = buildTable["TargetName"].AsString();
			arguments.TargetType = (BuildTargetType)
				buildTable["TargetType"].AsInteger();
			arguments.LanguageStandard = (LanguageStandard)
				buildTable["LanguageStandard"].AsInteger();
			arguments.SourceRootDirectory = new Path(buildTable["SourceRootDirectory"].AsString());
			arguments.TargetRootDirectory = new Path(buildTable["TargetRootDirectory"].AsString());
			arguments.ObjectDirectory = new Path(buildTable["ObjectDirectory"].AsString());
			arguments.BinaryDirectory = new Path(buildTable["BinaryDirectory"].AsString());

			if (buildTable.TryGetValue("ResourcesFile", out var resourcesFile))
			{
				arguments.ResourceFile = new Path(resourcesFile.AsString());
			}

			if (buildTable.TryGetValue("ModuleInterfacePartitionSourceFiles", out var moduleInterfacePartitionSourceFiles))
			{
				var paritionTargets = new List<PartitionSourceFile>();
				foreach (var partition in moduleInterfacePartitionSourceFiles.AsList())
				{
					var partitionTable = partition.AsTable();

					var partitionImports = new List<Path>();
					if (partitionTable.TryGetValue("Imports", out var partitionImportsValue))
					{
						partitionImports = partitionImportsValue.AsList().Select(value => new Path(value.AsString())).ToList();
					}

					paritionTargets.Add(new PartitionSourceFile()
					{
						File = new Path(partitionTable["Source"].AsString()),
						Imports = partitionImports,
					});
				}

				arguments.ModuleInterfacePartitionSourceFiles = paritionTargets;
			}

			if (buildTable.TryGetValue("ModuleInterfaceSourceFile", out var moduleInterfaceSourceFile))
			{
				arguments.ModuleInterfaceSourceFile = new Path(moduleInterfaceSourceFile.AsString());
			}

			if (buildTable.TryGetValue("Source", out var sourceValue))
			{
				arguments.SourceFiles = sourceValue.AsList().Select(value => new Path(value.AsString())).ToList();
			}

			if (buildTable.TryGetValue("AssemblySource", out var assemblySourceValue))
			{
				arguments.AssemblySourceFiles = assemblySourceValue.AsList().Select(value => new Path(value.AsString())).ToList();
			}

			if (buildTable.TryGetValue("IncludeDirectories", out var includeDirectoriesValue))
			{
				arguments.IncludeDirectories = includeDirectoriesValue.AsList().Select(value => new Path(value.AsString())).ToList();
			}

			if (buildTable.TryGetValue("PlatformLibraries", out var platformLibrariesValue))
			{
				arguments.PlatformLinkDependencies = platformLibrariesValue.AsList().Select(value => new Path(value.AsString())).ToList();
			}

			if (buildTable.TryGetValue("LinkLibraries", out var linkLibrariesValue))
			{
				arguments.LinkDependencies = MakeUnique(linkLibrariesValue.AsList().Select(value => new Path(value.AsString())));
			}

			if (buildTable.TryGetValue("LibraryPaths", out var libraryPathsValue))
			{
				arguments.LibraryPaths = libraryPathsValue.AsList().Select(value => new Path(value.AsString())).ToList();
			}

			if (buildTable.TryGetValue("PreprocessorDefinitions", out var preprocessorDefinitionsValue))
			{
				arguments.PreprocessorDefinitions = preprocessorDefinitionsValue.AsList().Select(value => value.AsString()).ToList();
			}

			if (buildTable.TryGetValue("OptimizationLevel", out var optimizationLevelValue))
			{
				arguments.OptimizationLevel = (BuildOptimizationLevel)
					optimizationLevelValue.AsInteger();
			}
			else
			{
				arguments.OptimizationLevel = BuildOptimizationLevel.None;
			}

			if (buildTable.TryGetValue("GenerateSourceDebugInfo", out var generateSourceDebugInfoValue))
			{
				arguments.GenerateSourceDebugInfo = generateSourceDebugInfoValue.AsBoolean();
			}
			else
			{
				arguments.GenerateSourceDebugInfo = false;
			}

			// Load the runtime dependencies
			if (buildTable.TryGetValue("RuntimeDependencies", out var runtimeDependenciesValue))
			{
				arguments.RuntimeDependencies = MakeUnique(
					runtimeDependenciesValue.AsList().Select(value => new Path(value.AsString())));
			}

			// Load the link dependencies
			if (buildTable.TryGetValue("LinkDependencies", out var linkDependenciesValue))
			{
				arguments.LinkDependencies = CombineUnique(
					arguments.LinkDependencies,
					linkDependenciesValue.AsList().Select(value => new Path(value.AsString())));
			}

			// Load the module references
			if (buildTable.TryGetValue("ModuleDependencies", out var moduleDependenciesValue))
			{
				arguments.ModuleDependencies = MakeUnique(
					moduleDependenciesValue.AsList().Select(value => new Path(value.AsString())));
			}

			// Load the list of disabled warnings
			if (buildTable.TryGetValue("EnableWarningsAsErrors", out var enableWarningsAsErrorsValue))
			{
				arguments.EnableWarningsAsErrors = enableWarningsAsErrorsValue.AsBoolean();
			}
			else
			{
				arguments.GenerateSourceDebugInfo = false;
			}

			// Load the list of disabled warnings
			if (buildTable.TryGetValue("DisabledWarnings", out var disabledWarningsValue))
			{
				arguments.DisabledWarnings = disabledWarningsValue.AsList().Select(value => value.AsString()).ToList();
			}

			// Check for any custom compiler flags
			if (buildTable.TryGetValue("CustomCompilerProperties", out var customCompilerPropertiesValue))
			{
				arguments.CustomProperties = customCompilerPropertiesValue.AsList().Select(value => value.AsString()).ToList();
			}

			// Initialize the compiler to use
			var compilerName = parametersTable["Compiler"].AsString();
			if (!this.compilerFactory.TryGetValue(compilerName, out var compileFactory))
			{
				this.buildState.LogTrace(TraceLevel.Error, "Unknown compiler: " + compilerName);
				throw new InvalidOperationException();
			}

			var compiler = compileFactory(activeState);

			var buildEngine = new BuildEngine(compiler);
			var buildResult = buildEngine.Execute(this.buildState, arguments);

			// Pass along internal state for other stages to gain access
			buildTable.EnsureValueList(this.factory, "InternalLinkDependencies").SetAll(this.factory, buildResult.InternalLinkDependencies);

			// Always pass along required input to shared build tasks
			var sharedBuildTable = sharedState.EnsureValueTable(this.factory, "Build");
			sharedBuildTable.EnsureValueList(this.factory, "ModuleDependencies").SetAll(this.factory, buildResult.ModuleDependencies);
			sharedBuildTable.EnsureValueList(this.factory, "RuntimeDependencies").SetAll(this.factory, buildResult.RuntimeDependencies);
			sharedBuildTable.EnsureValueList(this.factory, "LinkDependencies").SetAll(this.factory, buildResult.LinkDependencies);

			if (!buildResult.TargetFile.IsEmpty)
			{
				sharedBuildTable["TargetFile"] = this.factory.Create(buildResult.TargetFile.ToString());
				sharedBuildTable["RunExecutable"] = this.factory.Create(buildResult.TargetFile.ToString());
				sharedBuildTable.EnsureValueList(this.factory, "RunArguments").SetAll(this.factory, new List<string>() { });
			}

			// Register the build operations
			foreach (var operation in buildResult.BuildOperations)
			{
				this.buildState.CreateOperation(operation);
			}

			this.buildState.LogTrace(TraceLevel.Information, "Build Generate Done");
		}

		private static List<Path> CombineUnique(
			IEnumerable<Path> collection1,
			IEnumerable<Path> collection2)
		{
			var valueSet = new HashSet<string>();
			foreach (var value in collection1)
				valueSet.Add(value.ToString());
			foreach (var value in collection2)
				valueSet.Add(value.ToString());

			return valueSet.Select(value => new Path(value)).ToList();
		}

		private static List<Path> MakeUnique(IEnumerable<Path> collection)
		{
			var valueSet = new HashSet<string>();
			foreach (var value in collection)
				valueSet.Add(value.ToString());

			return valueSet.Select(value => new Path(value)).ToList();
		}
	}
}
