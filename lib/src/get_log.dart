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

Future<String> getLog(String builder, String build, String test) async {
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
    return logs
        .where((log) => log["name"].startsWith(test))
        .map((log) => log["log"])
        .join("\n========================================================\n");
  } catch (e) {
    return null;
  }
}
