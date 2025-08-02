import 'dart:async';

import 'utils/build_util.dart' as build;
import 'targets/dart_sdk.dart' as dart_sdk;
import 'targets/dartcc_app.dart' as app;
import 'utils/runner_util.dart';

final Map<String, List<build.Step>> targets = {
  "app": app.processSteps,
  "dart_sdk": dart_sdk.processSteps,
};

FutureOr<int> main(List<String> args) => Command(
  use: "build",
  description: "Targets: " + targets.keys.join(", "),
  run: (data) async {
    if (data.arg.isEmpty) {
      return CommandResponse(
        message: "Please specify a target.",
        syntax: data.cmd,
      );
    }
    if (!targets.keys.contains(data.arg)) {
      return CommandResponse(
        message:
            "Your target is invalid. Please specify an existing target: " +
            targets.keys.join(";") +
            ".",
        error: true,
      );
    }
    final bool force =
        data.flags.firstWhereOrNull((e) => (e.name == "force")) != null;
    final Flag? stepsFlag = data.flags.firstWhereOrNull(
      (e) => (e.name == "steps"),
    );
    final List<int>? steps = stepsFlag?.value
        .split(";")
        .map<int>((e) => int.parse(e))
        .toList();

    final environment = build.Environment(data.arg);
    if (steps != null) {
      final int length = targets[data.arg]!.length;
      for (int i = 0; i < length; i++) {
        final build.Step target = targets[data.arg]![i];

        if (target.configure != null) {
          await target.configure!(environment);
        }
        bool execute = true;
        if (target.condition != null && !force) {
          execute = await target.condition!(environment);
        }
        if (steps.contains(i + 1) && execute) {
          if (!await target.execute(
            environment,
            message: "(${i + 1}/$length) " + target.name,
          )) {
            return CommandResponse(
              message: "An error occurred at step ${i + 1}.",
            );
          }
        }
      }
      return CommandResponse(
        message: "Executed steps " + steps.join(", ") + ".",
      );
    }

    if (await environment.execute(targets[data.arg]!)) {
      return CommandResponse(message: "Executed successfully.");
    }
    return CommandResponse(error: true);
  },
  hidden: true,
  flags: [
    Flag(
      name: "force",
      description:
          "Ignore conditions and enforce the execution of steps.",
    ),
    Flag(
      name: "steps",
      description: "Just execute several, specified, steps.",
      overview: ["1", "3", "2;5;1"],
    ),
  ],
).execute(args);
