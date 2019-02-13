#!/usr/bin/env dart
// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Serves the log over HTTP for a failing test on a given runner and build

import 'dart:async';
import 'dart:io';

import 'package:log/src/get_log.dart';
import 'package:http/http.dart' as http;

void main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  server.listen(logServer);
  print("Server started at ip:port ${server.address}:${server.port}");
}

void logServer(HttpRequest request) async {
  try {
    if (!request.uri.path.startsWith('/log/')) {
      notFound(request);
      return;
    }
    final parts = request.uri.pathSegments;
    final builder = parts[1];
    final build = parts[2];
    final test = parts.skip(3).join('/');
    final log = await getLog(builder, build, test);
    if (log == null) {
      noLog(request, builder, build, test);
      return;
    }
    final response = request.response;
    response.headers.contentType = ContentType.text;
    response.headers.expires = DateTime.now().add(Duration(days: 30));
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
