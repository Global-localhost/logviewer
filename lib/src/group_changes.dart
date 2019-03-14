// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Add fields with data about the test run and the commit tested, and
// with the result on the last build tested, to the test results file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:resource/resource.dart' show Resource;

//import 'results.dart';

class MinMax {
  int min = null;
  int max = null;

  void add(int value) {
    if (value == null) return;
    if (min == null || value < min) min = value;
    if (max == null || value > max) max = value;
  }

  String toString() => "($min:$max)";
}

// List<String> hashes;
//List<String> commitData;

class ByConfigSetData {
  String formattedConfigSet;
  String test; // Test name, including suite
  String change; // Change in results, reported as string "was, now, expected"
  MinMax before; // MinMax of indices of commits before this change
  MinMax after; // MinMax of indices of commits after or at this change.

  ByConfigSetData(
      this.formattedConfigSet, this.test, this.change, this.before, this.after);
}
main() async {
  print( await createChangesPage());
}

Future<String> createChangesPage() async {
  
    final changesPath = Resource("package:log/src/resources/changes.json");
    final commitDataPath = Resource("package:log/src/resources/commit_list.txt");

  // Load the input and the flakiness data if specified.
  final changes = await loadJsonLines(changesPath) as List<dynamic>;
  var lines = await loadLines(commitDataPath);
  var hashes = <String>[];
  var commitData = <String>[];
  var reviewLinks = <String>[];
  var line = lines.iterator;
  bool reviewExpected = false;
  while (line.moveNext()) {
    if (line.current == 'dart-results-feed-commit-entry') {
      if (reviewExpected) {
        reviewLinks.add("https://dart.googlesource.com/sdk/+/${hashes.last}");
      }
      line.moveNext();
      hashes.add(line.current.substring(0, 40));
      commitData.add(line.current.substring(46, 57) + line.current.substring(66));
      reviewExpected = true;
    }
    const reviewPrefix = "Reviewed-on: ";
    if (line.current.startsWith(reviewPrefix) && reviewExpected) {
      reviewLinks.add(line.current.substring(reviewPrefix.length));
      reviewExpected = false;
    }
  }
  final data = computePageData(changes, hashes);
  return htmlPage(data, hashes, commitData, reviewLinks);
}



  Map<int, Map<int, Map<String, List<ByConfigSetData>>>> computePageData(List<dynamic> changes,
                                                                         List<String> hashes) {
  final Map<String, int> hashIndex = Map.fromEntries(
      Iterable.generate(hashes.length, (i) => MapEntry(hashes[i], i)));

  final resultsForTestAndChange =
      Map<String, Map<String, List<Map<String, dynamic>>>>();

  for (final Map<String, dynamic> change in changes) {
    final configsForName = resultsForTestAndChange.putIfAbsent(
        change['name'], () => Map<String, List<Map<String, dynamic>>>());
    final key =
        '${change['previous_result']} -> ${change['result']}  (expected ${change['expected']})';
    configsForName.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(change);
  }

  final data = List<ByConfigSetData>();
  
  
  for (final test in resultsForTestAndChange.keys) {
    for (final results in resultsForTestAndChange[test].keys) {
      var changes = resultsForTestAndChange[test][results];
      while (changes.isNotEmpty) {
        var before = MinMax();
        for (var change in changes) {
          before.add(hashIndex[change["previous_commit_hash"]]);
        }
        // Sort changes by before, take all where after < first before, repeat
        var firstSection = changes.where((change) => hashIndex[change["commit_hash"]] < before.min).toList();
        changes =  changes.where((change) => hashIndex[change["commit_hash"]] >= before.min).toList();
        final configs = <String>[];
        before = MinMax();
        final after = MinMax();
        for (var change in firstSection) {
          configs.add(change["configuration"]);
          before.add(hashIndex[change["previous_commit_hash"]]);
          after.add(hashIndex[change["commit_hash"]]);
        }
        configs.sort();
        final formattedSet = configs.join(",<br>") ;
        data.add(ByConfigSetData(formattedSet, test, results, before, after));
      }
    }
  }

  final byBlamelist = Map<int, Map<int, Map<String, List<ByConfigSetData>>>>();
  for (var change in data) {
    byBlamelist
        .putIfAbsent(change.after.max,
            () => Map<int, Map<String, List<ByConfigSetData>>>())
        .putIfAbsent(
            change.before.min, () => Map<String, List<ByConfigSetData>>())
        .putIfAbsent(change.formattedConfigSet, () => List<ByConfigSetData>())
        .add(change);
  }

  return byBlamelist;
  }

String prelude() => '''
<!DOCTYPE html><html><head><title>Results Feed</title>
<style>
      td {background-color: white; font-family: monospace;}
td.blamelist {background-color: powderblue; padding: 10px;} 
h1   {color: blue;}
td    {vertical-align: top;}
td.outer    {padding: 10px;}
span.green {background-color: SpringGreen;}
</style>
<script>function showBlamelist(id) {
  if (document.getElementById(id + "-off").style.display == "none") {
    document.getElementById(id + "-on").style.display = "none";
      document.getElementById(id + "-off").style.display = "block";
  } else
  {
    document.getElementById(id + "-off").style.display = "none";
      document.getElementById(id + "-on").style.display = "block";
  }
}
</script>
</head><body><h1>Results Feed</h1>
''';

String postlude() => '''</body></html>''';

String htmlPage(Map<int, Map<int, Map<String, List<ByConfigSetData>>>> data, List<String> hashes, List<String> commitData, List<String> reviewLinks) {
  StringBuffer page = StringBuffer(prelude());

  page.write("<table>");
  var after = MinMax();
  data.keys.forEach(after.add);
  print(after.min);
  print(after.max);
  for (var afterKey = 0; afterKey <= after.max; ++afterKey) {
    // Print info about this commit:
    page.write("<tr><td colspan='3'><h3>${commitData[afterKey]}</h3><a href='${reviewLinks[afterKey]}'>${hashes[afterKey]}</a></td></tr>");
    if (!data.containsKey(afterKey)) continue;    
    var beforeKeys = data[afterKey].keys.toList()..sort();
    for (var beforeKey in beforeKeys) {
      page.write("<tr><td class='blamelist' colspan='3'>");
      if (beforeKey <= afterKey) {
        page.write(
            "invalid (empty) blamelist: before is after after: $afterKey $beforeKey");
        page.write(
            "Change first appeared on or after ${hashes[afterKey]} ${commitData[afterKey]}");
        } else {
          void writeChange(int i) {
            page.write("&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; <a href='${reviewLinks[i]}'>${hashes[i]}</a> ${commitData[i]}<br>");
          }
        var size = beforeKey - afterKey;
        page.write("blamelist has $size change${size > 1 ? 's' : ''}:<br>");
        const int summarize_size = 6;
        if (size < summarize_size) {
          for (int i = afterKey; i < beforeKey; ++i) {
            writeChange(i);
          }
        }
        else {
          var id = '$afterKey-$beforeKey';
          page.write("<div onclick='showBlamelist(\"$id\")'>");
          for (int i = afterKey; i < afterKey + 3 ; ++i) {
            writeChange(i);
          }
          page.write("<div class='expand_off' id='$id-off'> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;...</div>");
          page.write("<div class='expand_on' id='$id-on' style='display:none'>");
          for (int i = afterKey + 3; i < beforeKey -1 ; ++i) {
            writeChange(i);
          }
          page.write("</div>");
          writeChange(beforeKey - 1);
          page.write("</div>");
        }
      }
      page.write("</td></tr>");
      var configSetKeys = data[afterKey][beforeKey].keys.toList()
        ..sort();
      for (var configSetKey in configSetKeys) {
        page.write("<tr><td class='outer'>");
        page.write("<span class='green'>These tests changed in these ways:</span><br><table>");
        final tests = data[afterKey][beforeKey][configSetKey]..sort((a, b) => a.test.compareTo(b.test));
        final numTests = tests.length;
        for (final test in tests) {
          page.write("<tr><td>&nbsp;&nbsp;&nbsp;&nbsp;${test.test}</td><td> &nbsp;&nbsp;${test.change}</td></tr>");
        }
        page.write("</table></td><td class='outer'>");
        
        page.write("<span class='green'>on these configurations:</span><div style='column-count:2; lineHeight:2'>$configSetKey</div>");
        page.write("</td></tr>");
      }
    }
  }
  page.write("</table>");
  page.write(postlude());
  return page.toString();
}

Future<List<String>> loadLines(Resource resource) => resource
    .openRead()
    .transform(utf8.decoder)
    .transform(LineSplitter())
    .toList();

Future<Object> loadJson(Resource resource) async {
  final json = await resource.openRead().transform(utf8.decoder).join();
  return jsonDecode(json);
}

Future<Object> loadJsonLines(Resource resource) async {
  final json = await resource.openRead().transform(utf8.decoder).transform(LineSplitter()).toList();
  return List<Map<String,dynamic>>.from(json.map(jsonDecode));
}
