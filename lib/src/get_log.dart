#!/usr/bin/env dart
// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Displays the log for a failing test on a given runner and build

import 'dart:async';
import 'dart:convert';

import 'package:_discoveryapis_commons/_discoveryapis_commons.dart';
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:http/http.dart' as http;

Future<String> getCloudFile(String bucket, String path) async {
  var client = http.Client();
  try {
    var api = storage.StorageApi(client);
    var media = await api.objects
        .get(bucket, path, downloadOptions: DownloadOptions.FullMedia) as Media;
    return await utf8.decodeStream(media.stream);
  } finally {
    client.close();
  }
}

Future<String> getApproval(String builder) async {
  try {
    final bucket = "dart-test-results";
    String build = await getCloudFile(bucket, "builders/$builder/latest");
    return await getCloudFile(bucket, "builders/$builder/$build/approved_results.json");
  } catch (e) {
    print(e);
    return null;
  }
}

Future<String> getLog(
    String builder, String build, String configuration, String test) async {
  try {
    final bucket = "dart-test-results";
    if (build == "latest") {
      build = await getCloudFile(bucket, "builders/$builder/latest");
    }
    final logs_json =
        await getCloudFile(bucket, "builders/$builder/$build/logs.json");
    final logs = logs_json
        .split('\n')
        .where((line) => line != "")
        .map(jsonDecode)
        .toList();
    var testFilter = (log) => log["name"] == test;
    if (test.endsWith("*")) {
      final prefix = test.substring(0, test.length - 1);
      testFilter = (log) => log["name"].startsWith(prefix);
    }
    var configurationFilter = (log) => log["configuration"] == configuration;
    if (configuration.endsWith("*")) {
      final prefix = configuration.substring(0, configuration.length - 1);
      configurationFilter = (log) => log["configuration"].startsWith(prefix);
    }
    var result = logs
        .where((log) => testFilter(log) && configurationFilter(log))
        .map((log) => log["log"])
        .join("\n\n======================================================\n\n");
    if (result.isEmpty) return null;
    return result;
  } catch (e) {
    return null;
  }
}
