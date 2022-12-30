﻿// <copyright file="ResolveToolsTask.cs" company="Soup">
// Copyright (c) Soup. All rights reserved.
// </copyright>

using Opal;
using Opal.System;
using System;
using System.Collections.Generic;

namespace Soup.Build.Cpp
{
	/// <summary>
	/// The recipe build task that knows how to build a single recipe
	/// </summary>
	public class ResolveToolsTask : IBuildTask
	{
		private IBuildState buildState;
		private IValueFactory factory;

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

		public ResolveToolsTask(IBuildState buildState, IValueFactory factory)
		{
			this.buildState = buildState;
			this.factory = factory;
		}

		/// <summary>
		/// The Core Execute task
		/// </summary>
		public void Execute()
		{
			var state = this.buildState.ActiveState;
			var parameters = state["Parameters"].AsTable();

			var systemName = parameters["System"].AsString();
			var architectureName = parameters["Architecture"].AsString();

			if (systemName != "win32")
				throw new InvalidOperationException("Win32 is the only supported system... so far.");

			// Check if skip platform includes was specified
			bool skipPlatform = false;
			if (state.TryGetValue("SkipPlatform", out var skipPlatformValue))
			{
				skipPlatform = skipPlatformValue.AsBoolean();
			}

			// Find the MSVC SDK
			var msvcSDKProperties = GetSDKProperties("MSVC", parameters);

			// Use the default version
			var visualCompilerVersion = msvcSDKProperties["Version"].AsString();
			this.buildState.LogTrace(TraceLevel.Information, "Using VC Version: " + visualCompilerVersion);

			// Get the final VC tools folder
			var visualCompilerVersionFolder = new Path(msvcSDKProperties["VCToolsRoot"].AsString());

			// Load the Windows sdk
			var windowsSDKProperties = GetSDKProperties("Windows", parameters);

			// Calculate the windows kits directory
			var windows10KitPath = new Path(windowsSDKProperties["RootPath"].AsString());
			var windows10KitIncludePath = windows10KitPath + new Path("./include/");
			var windows10KitBinPath = windows10KitPath + new Path("./bin/");
			var windows10KitLibPath = windows10KitPath + new Path("./Lib/");

			var windowsKitVersion = windowsSDKProperties["Version"].AsString();

			this.buildState.LogTrace(TraceLevel.Information, "Using Windows Kit Version: " + windowsKitVersion);
			var windows10KitVersionIncludePath = windows10KitIncludePath + new Path(windowsKitVersion + "/");
			var windows10KitVersionBinPath = windows10KitBinPath + new Path(windowsKitVersion + "/");
			var windows10KitVersionLibPath = windows10KitLibPath + new Path(windowsKitVersion + "/");

			// Set the VC tools binary folder
			Path vcToolsBinaryFolder;
			Path windosKitsBinaryFolder;
			if (architectureName == "x64")
			{
				vcToolsBinaryFolder = visualCompilerVersionFolder + new Path("./bin/Hostx64/x64/");
				windosKitsBinaryFolder = windows10KitVersionBinPath + new Path("x64/");
			}
			else if (architectureName == "x86")
			{
				vcToolsBinaryFolder = visualCompilerVersionFolder + new Path("./bin/Hostx64/x86/");
				windosKitsBinaryFolder = windows10KitVersionBinPath + new Path("x86/");
			}
			else
			{
				throw new InvalidOperationException("Unknown architecture.");
			}

			var clToolPath = vcToolsBinaryFolder + new Path("cl.exe");
			var linkToolPath = vcToolsBinaryFolder + new Path("link.exe");
			var libToolPath = vcToolsBinaryFolder + new Path("lib.exe");
			var mlToolPath = vcToolsBinaryFolder + new Path("ml64.exe");
			var rcToolPath = windosKitsBinaryFolder + new Path("rc.exe");

			// Save the build properties
			state["MSVC.Version"] = this.factory.Create(visualCompilerVersion);
			state["MSVC.VCToolsRoot"] = this.factory.Create(visualCompilerVersionFolder.toString);
			state["MSVC.VCToolsBinaryRoot"] = this.factory.Create(vcToolsBinaryFolder.toString);
			state["MSVC.WindosKitsBinaryRoot"] = this.factory.Create(windosKitsBinaryFolder.toString);
			state["MSVC.LinkToolPath"] = this.factory.Create(linkToolPath.toString);
			state["MSVC.LibToolPath"] = this.factory.Create(libToolPath.toString);
			state["MSVC.RCToolPath"] = this.factory.Create(rcToolPath.toString);
			state["MSVC.MLToolPath"] = this.factory.Create(mlToolPath.toString);

			// Allow custom overrides for the compiler path
			if (!state.ContainsKey("MSVC.ClToolPath"))
				state["MSVC.ClToolPath"] = this.factory.Create(clToolPath.toString);

			// Set the include paths
			var platformIncludePaths = new List<Path>();
			if (!skipPlatform)
			{
				platformIncludePaths = new List<Path>()
				{
					visualCompilerVersionFolder + new Path("./include/"),
					windows10KitVersionIncludePath + new Path("./ucrt/"),
					windows10KitVersionIncludePath + new Path("./um/"),
					windows10KitVersionIncludePath + new Path("./winrt/"),
					windows10KitVersionIncludePath + new Path("./shared/"),
				};
			}

			// Set the include paths
			var platformLibraryPaths = new List<Path>();
			if (!skipPlatform)
			{
				if (architectureName == "x64")
				{
					platformLibraryPaths.Add(windows10KitVersionLibPath + new Path("./ucrt/x64/"));
					platformLibraryPaths.Add(windows10KitVersionLibPath + new Path("./um/x64/"));
					platformLibraryPaths.Add(visualCompilerVersionFolder + new Path("./atlmfc/lib/x64/"));
					platformLibraryPaths.Add(visualCompilerVersionFolder + new Path("./lib/x64/"));
				}
				else if (architectureName == "x86")
				{
					platformLibraryPaths.Add(windows10KitVersionLibPath + new Path("./ucrt/x86/"));
					platformLibraryPaths.Add(windows10KitVersionLibPath + new Path("./um/x86/"));
					platformLibraryPaths.Add(visualCompilerVersionFolder + new Path("./atlmfc/lib/x86/"));
					platformLibraryPaths.Add(visualCompilerVersionFolder + new Path("./lib/x86/"));
				}
			}

			// Set the platform definitions
			var platformPreprocessorDefinitions = new List<string>()
			{
				// "this.DLL", // Link against the dynamic runtime dll
				// "this.MT", // Use multithreaded runtime
			};

			if (architectureName == "x86")
				platformPreprocessorDefinitions.Add("WIN32");

			// Set the platform libraries
			var platformLibraries = new List<Path>()
			{
				new Path("kernel32.lib"),
				new Path("user32.lib"),
				new Path("gdi32.lib"),
				new Path("winspool.lib"),
				new Path("comdlg32.lib"),
				new Path("advapi32.lib"),
				new Path("shell32.lib"),
				new Path("ole32.lib"),
				new Path("oleaut32.lib"),
				new Path("uuid.lib"),
				// Path("odbc32.lib"),
				// Path("odbccp32.lib"),
				// Path("crypt32.lib"),
			};

			// if (this.options.Configuration == "debug")
			// {
			// 	// arguments.PlatformPreprocessorDefinitions.pushthis.back("this.DEBUG");
			// 	arguments.PlatformLibraries = std::vector<Path>({
			// 		Path("msvcprtd.lib"),
			// 		Path("msvcrtd.lib"),
			// 		Path("ucrtd.lib"),
			// 		Path("vcruntimed.lib"),
			// 	});
			// }
			// else
			// {
			// 	arguments.PlatformLibraries = std::vector<Path>({
			// 		Path("msvcprt.lib"),
			// 		Path("msvcrt.lib"),
			// 		Path("ucrt.lib"),
			// 		Path("vcruntime.lib"),
			// 	});
			// }

			state.EnsureValueList(this.factory, "PlatformIncludePaths").SetAll(this.factory, platformIncludePaths);
			state.EnsureValueList(this.factory, "PlatformLibraryPaths").SetAll(this.factory, platformLibraryPaths);
			state.EnsureValueList(this.factory, "PlatformLibraries").SetAll(this.factory, platformLibraries);
			state.EnsureValueList(this.factory, "PlatformPreprocessorDefinitions").SetAll(this.factory, platformPreprocessorDefinitions);
		}

		private IValueTable GetSDKProperties(string name, IValueTable state)
		{
			foreach (var sdk in state["SDKs"].AsList())
			{
				var sdkTable = sdk.AsTable();
				if (sdkTable.TryGetValue("Name", out var nameValue))
				{
					if (nameValue.AsString() == name)
					{
						return sdkTable["Properties"].AsTable();
					}
				}
			}

			throw new InvalidOperationException($"Missing SDK {name}");
		}
	}
}
