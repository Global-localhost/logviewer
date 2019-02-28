#!/usr/bin/env dart
// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Serves the log over HTTP for a failing test on a given runner and build

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:log/src/get_log.dart';
import 'package:http/http.dart' as http;

const builders = [
  "analyzer-analysis-server-linux",
  "analyzer-linux-release",
  "analyzer-mac-release",
  "analyzer-win-release",
  "app-kernel-linux-debug-x64",
  "app-kernel-linux-product-x64",
  "app-kernel-linux-release-x64",
  "cross-vm-linux-release-arm64",
  "dart2js-csp-minified-linux-x64-chrome",
  "dart2js-minified-strong-linux-x64-d8",
  "dart2js-strong-hostasserts-linux-ia32-d8",
  "dart2js-strong-linux-x64-chrome",
  "dart2js-strong-linux-x64-firefox",
  "dart2js-strong-mac-x64-chrome",
  "dart2js-strong-mac-x64-safari",
  "dart2js-strong-win-x64-chrome",
  "dart2js-strong-win-x64-firefox",
  "dart2js-strong-win-x64-ie11",
  "dart2js-unit-linux-x64-release",
  "ddc-linux-release-chrome",
  "ddc-mac-release-chrome",
  "ddc-win-release-chrome",
  "front-end-linux-release-x64",
  "front-end-mac-release-x64",
  "front-end-win-release-x64",
  "pkg-linux-debug",
  "pkg-linux-release",
  "pkg-mac-release",
  "pkg-win-release",
  "vm-canary-linux-debug",
  "vm-dartkb-linux-debug-x64",
  "vm-dartkb-linux-release-x64",
  "vm-kernel-asan-linux-release-x64",
  "vm-kernel-checked-linux-release-x64",
  "vm-kernel-linux-debug-ia32",
  "vm-kernel-linux-debug-simdbc64",
  "vm-kernel-linux-debug-x64",
  "vm-kernel-linux-product-x64",
  "vm-kernel-linux-release-ia32",
  "vm-kernel-linux-release-simarm",
  "vm-kernel-linux-release-simarm64",
  "vm-kernel-linux-release-simdbc64",
  "vm-kernel-linux-release-x64",
  "vm-kernel-mac-debug-simdbc64",
  "vm-kernel-mac-debug-x64",
  "vm-kernel-mac-product-x64",
  "vm-kernel-mac-release-simdbc64",
  "vm-kernel-mac-release-x64",
  "vm-kernel-optcounter-threshold-linux-release-ia32",
  "vm-kernel-optcounter-threshold-linux-release-x64",
  "vm-kernel-precomp-android-release-arm",
  "vm-kernel-precomp-bare-linux-release-simarm",
  "vm-kernel-precomp-bare-linux-release-simarm64",
  "vm-kernel-precomp-bare-linux-release-x64",
  "vm-kernel-precomp-linux-debug-x64",
  "vm-kernel-precomp-linux-product-x64",
  "vm-kernel-precomp-linux-release-simarm",
  "vm-kernel-precomp-linux-release-simarm64",
  "vm-kernel-precomp-linux-release-x64",
  "vm-kernel-precomp-mac-release-simarm64",
  "vm-kernel-precomp-obfuscate-linux-release-x64",
  "vm-kernel-precomp-win-release-simarm64",
  "vm-kernel-precomp-win-release-x64",
  "vm-kernel-reload-linux-debug-x64",
  "vm-kernel-reload-linux-release-x64",
  "vm-kernel-reload-mac-debug-simdbc64",
  "vm-kernel-reload-mac-release-simdbc64",
  "vm-kernel-reload-rollback-linux-debug-x64",
  "vm-kernel-reload-rollback-linux-release-x64",
  "vm-kernel-win-debug-ia32",
  "vm-kernel-win-debug-x64",
  "vm-kernel-win-product-x64",
  "vm-kernel-win-release-ia32",
  "vm-kernel-win-release-x64",
];

class ApprovalEvent {
  final approver;
  final approvedAt;

  ApprovalEvent(this.approver, this.approvedAt);

  final events = new SplayTreeSet<String>();
}

final approvalEvents = new SplayTreeMap<String, ApprovalEvent>();

void main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  server.listen(logServer);
  print("Server started at ip:port ${server.address}:${server.port}");
  getApprovals();
}

Future getApprovals() async {
  for (final builder in builders) {
    print("getting approval for $builder");
    final data = await getApproval(builder);
    for (final line in LineSplitter.split(data)) {
      final record = jsonDecode(line);
      final approver = record["approver"];
      final approvedAt = record["approved_at"];
      if (approver == null || approvedAt == null) {
        continue;
      }
      final approvalEvent = approvalEvents.putIfAbsent(approvedAt, () => new ApprovalEvent(approver, approvedAt));
      final configuration = record["configuration"];
      final suite = record["suite"];
      final testName = record["test_name"];
      final result = record["result"];
      final pass = record["pass"];
      final what = record["matches"] ? "succeeding" : result;
      final color = record["matches"] ? "green" : "red";
      final event = "<td>$suite/$testName</td><td><b style='color: $color;'>$what</b></td><td>$builder</td><td>$configuration</td>";
      approvalEvent.events.add(event);
    }
  }
}

void approval(HttpRequest request) async {
  request.response.headers.contentType = ContentType.html;
  request.response.write("""<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Approval</title>
  </head>
  <body>
    <h1>Approvals</h1>
""");
  for (final approvalEvent in approvalEvents.values.toList().reversed.take(100)) {
    request.response.write("<h2>${approvalEvent.approvedAt.replaceAll("T", " ").substring(0, 19)} ${approvalEvent.approver} approved</h2>\n");
    request.response.write("<table>");
    for (final event in approvalEvent.events) {
      request.response.write("<tr>$event</tr>");
    }
    request.response.write("</table>\n");
  }
  request.response.write("""  </body>
</html>
""");
  request.response.close();
}

void logServer(HttpRequest request) async {
  try {
    if (request.uri.path.startsWith('/approval/')) {
      approval(request);
      return;
    }
    if (!request.uri.path.startsWith('/log/')) {
      notFound(request);
      return;
    }
    final parts = request.uri.pathSegments;
    final builder = parts[1];
    final configuration = parts[2];
    final build = parts[3];
    final test = parts.skip(4).join('/');
    final log = await getLog(builder, build, configuration, test);
    if (log == null) {
      noLog(request, builder, build, test);
      return;
    }
    final response = request.response;
    response.headers.contentType = ContentType.text;
    var expires = DateTime.now();
    if (build != 'latest') {
      expires = expires.add(Duration(days: 30));
    }
    response.headers.expires = expires;    
    response.write(log);
    response.close();
  } catch (e, t) {
    print(e);
    print(t);
    serverError(request);
  }
}

void notFound(request) {
  request.response.statusCode = HttpStatus.notFound;
  request.response.close();
}

void noLog(request, String builder, String build, String test) {
  request.response.headers.contentType = ContentType.text;
  request.response
      .write("No log for test $test on build $build of builder $builder");
  request.response.close();
}

void serverError(request) {
  request.response.statusCode = HttpStatus.internalServerError;
  request.response.close();
}
