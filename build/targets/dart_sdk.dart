/*
 * Copyright (c) 2025 Lenny Siebert
 *
 * This software is dual-licensed:
 *
 * 1. Open Source License:
 *    This program is free software: you can redistribute it and/or modify
 *    it under the terms of the GNU General Public License version 3
 *    as published by the Free Software Foundation.
 *    This program is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY. See the GNU General Public
 *    License for more details: https://www.gnu.org/licenses/gpl-3.0.en.html
 *
 * 2. Commercial License:
 *    A commercial license will be available at a later time for use in commercial products.
 *
 */

import 'dart:io';

import 'package:path/path.dart' as path;
import '../utils/build_util.dart';

List<Step> processSteps = [
  Step(
    "Ensures required programs in environment",
    run: (env) => env.ensurePrograms(["python", "git", "dart"]),
  ),
  /**
   * The chromium toolchain has to be cloned first.
   */
  Step(
    "Clone depot tools repository",
    configure: (env) {
      env.vars["depot_tools_url"] =
          "https://chromium.googlesource.com/chromium/tools/depot_tools.git";
      env.vars["depot_tools_path"] = path.join(
        env.workDirectoryPath,
        path.basenameWithoutExtension(env.vars["depot_tools_url"]),
      );
    },
    condition: (env) {
      env.vars["depot_tools_existed"] = Directory(
        env.vars["depot_tools_path"],
      ).existsSync();
      return !env.vars["depot_tools_existed"];
    },
    command: (env) => StepCommand(
      program: "git",
      arguments: ["clone", env.vars["depot_tools_url"]],
    ),
    exitFail: false,
  ),
  /*
   * Changes the repository to the forked/modified one.
   */
  Step(
    "Set repository url",
    condition: (env) => !env.vars["depot_tools_existed"],
    run: (env) {
      bool success = true;
      try {
        final File dartConfig = File(
          path.join(env.vars["depot_tools_path"], "fetch_configs", "dart.py"),
        );
        final String dartConfigContent = dartConfig.readAsStringSync();
        dartConfig.deleteSync();
        dartConfig.createSync();
        dartConfig.writeAsStringSync(
          dartConfigContent.replaceAll(
            "https://dart.googlesource.com/sdk.git",
            "https://github.com/zopnote/dartcc-sdk.git",
          ),
        );
      } catch (e) {
        stderr.writeln(e);
        success = !success;
      }
      return success;
    },
  ),
  /**
   * The Dart SDK depend on the chromium toolchain and has to be fetched
   * with the depot_tools fetch tool. We set DEPOT_TOOLS_WIN_TOOLCHAIN,
   * because if we doesn't a google toolchain is downloaded to compile
   * C++ instead of the local installation of gcc or msvc.
   */
  Step(
    "Fetch the dart sdk",
    configure: (env) {
      if (env.host.platform == Platform.windows) {
        env.vars["DEPOT_TOOLS_WIN_TOOLCHAIN"] = 0;
      }
    },
    condition: (env) =>
        !Directory(path.join(env.workDirectoryPath, "sdk")).existsSync(),
    command: (env) => StepCommand(
      program: path.join(env.vars["depot_tools_path"], "fetch"),
      arguments: ["dart"],
      administrator: env.host.platform == Platform.windows,
    ),
    spinner: true,
  ),

  /**
   * gclient is a tool of google and is used in this context to download
   * all dependencies of the Dart SDK.
   */
  Step(
    "Synchronize gclient dependencies",
    configure: (env) {
      env.vars["dart_sdk_path"] = path.join(env.workDirectoryPath, "sdk");
      env.vars["gclient_script_file"] = path.join(
        env.vars["depot_tools_path"],
        "gclient" + (env.host.platform == Platform.windows ? ".bat" : ""),
      );
    },
    condition: (env) => !File(
      path.join(env.workDirectoryPath, ".gclient_previous_sync_commits"),
    ).existsSync(),
    command: (env) => StepCommand(
      program: env.vars["gclient_script_file"],
      arguments: ["sync"],
      workingDirectoryPath: env.vars["dart_sdk_path"],
      administrator: true,
    ),
    spinner: true,
  ),

  Step(
    "Resolve dart package dependencies",
    condition: (env) => !File(
      path.join(env.vars["dart_sdk_path"], ".dart_tool", "package_config.json"),
    ).existsSync(),
    command: (env) => StepCommand(
      program: "dart",
      arguments: ["pub", "get"],
      workingDirectoryPath: env.vars["dart_sdk_path"],
      administrator: true,
    ),
    spinner: true,
  ),

  /*
   * The cloned repository is a modified version of the dart-sdk, that builds the
   * supported cross compilers and dartaotruntimes for the platforms.
   */
  Step(
    "Build the required Dart SDK binaries",
    configure: (env) {
      if (env.target.platform == Platform.linux) {
        env.vars["dart_architectures"] = "x64,arm64,riscv64";
      } else if (env.target.platform == Platform.windows) {
        env.vars["dart_architectures"] = "x64,arm64";
      } else if (env.target.platform == Platform.macos) {
        env.vars["dart_architectures"] = "arm64";
      }
      env.vars["dart_binaries_paths"] =
          (env.vars["dart_architectures"] as String).split(",").map((e) {
            if (env.target.platform == Platform.macos) {
              return path.join(
                env.vars["dart_sdk_path"],
                "xcodebuild",
                "Product" + e.toUpperCase(),
              );
            }
            return path.join(
              env.vars["dart_sdk_path"],
              "out",
              "Product" + e.toUpperCase(),
            );
          });

      env.vars["dart_dependency_python"] = env.host.platform == Platform.windows
          ? path.join(env.vars["depot_tools_path"], "python3.bat")
          : "python";
    },
    condition: (env) {
      bool allExists = false;
      for (final String path in env.vars["dart_binaries_paths"]) {
        allExists = Directory(path).existsSync();
      }
      return !allExists;
    },
    command: (env) => StepCommand(
      program: env.vars["dart_dependency_python"],
      arguments: [
        "${env.vars["dart_sdk_path"]}/tools/build.py",
        "--mode",
        "product",
        "--arch",
        env.vars["dart_architectures"],
        "create_cc_all",
      ],
      workingDirectoryPath: env.vars["dart_sdk_path"],
    ),
  ),
];
