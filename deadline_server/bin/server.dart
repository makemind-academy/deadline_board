import 'dart:async';
import 'dart:convert';

import 'package:mcp_server/mcp_server.dart';

import 'serve_bundle.dart';

/// deadline_server — a bookkeeper's filing calendar, as tools.
///
/// What makes this domain hard is not the arithmetic. It is that the rule and
/// the date are different things, and offices routinely lose the rule.
///
/// A spreadsheet holds a day like "the 27th". Nobody who reads that cell can tell
/// whether it is the statutory date, a date pushed for a weekend, or a typo
/// from last year that was copied down. So this server never stores a due date.
/// It stores the **rule**, and computes the date every time — and hands back
/// both, so the screen can show the reason next to the day.
void main(List<String> args) async {
  const config = McpServerConfig(
    name: 'Deadlines',
    version: '1.0.0',
    capabilities: ServerCapabilities(
      tools: ToolsCapability(listChanged: true),
      resources: ResourcesCapability(listChanged: true),
    ),
  );
  final server = McpServer.createServer(config);
  DeadlineServer(server).register();
  // The screen next door: AppPlayer reads it from here and sends the pages'
  // tool calls back to the tools above.
  registerBundleUi(server, '../deadlines.mbd');
  final transport = McpServer.createStdioTransport().get();
  server.connect(transport);
  await Completer<void>().future;
}

/// A filing obligation, as a rule rather than a date.
class Duty {
  const Duty(this.client, this.name, this.dayOfMonth, this.monthOf, this.note);

  final String client;
  final String name;

  /// Statutory day of the month.
  final int dayOfMonth;

  /// Which month it lands in, relative to the period being filed.
  final int monthOf;

  final String note;
}

class DeadlineServer {
  DeadlineServer(this.server);

  final Server server;

  /// "Today" is fixed so the sample is reproducible; the article says so.
  static final _today = DateTime(2026, 4, 20);

  static String _fmt(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  final _duties = const [
    Duty('Brightwater', 'VAT — Q1', 25, 4, 'quarterly return'),
    Duty('Brightwater', 'Withholding — March', 10, 4, 'monthly'),
    Duty('Fairfield', 'VAT — Q1', 25, 4, 'quarterly return'),
    Duty('Fairfield', 'Corporate tax', 31, 3, 'annual, fiscal year ends Dec'),
    Duty('Northgate', 'Withholding — March', 10, 4, 'monthly'),
    Duty('Northgate', 'Local income tax', 30, 4, 'follows the corporate filing'),
  ];

  /// Shift a statutory date off a weekend, and say that you did.
  ///
  /// This is the rule everyone knows and every spreadsheet forgets. Returning
  /// the shift as text rather than silently moving the date is the whole point:
  /// "25th, moved to Monday" is checkable, "27th" is not.
  (DateTime, String) _resolve(Duty d) {
    var date = DateTime(2026, d.monthOf, d.dayOfMonth);
    if (date.weekday == DateTime.saturday) {
      return (date.add(const Duration(days: 2)), 'statutory ${d.dayOfMonth}th fell on Saturday');
    }
    if (date.weekday == DateTime.sunday) {
      return (date.add(const Duration(days: 1)), 'statutory ${d.dayOfMonth}th fell on Sunday');
    }
    return (date, '');
  }

  void register() {
    server.addTool(
      name: 'board.today',
      description:
          'Everything due, soonest first, with the rule that produced each date '
          'and how many days are left',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => _state(),
    );

    server.addTool(
      name: 'board.client',
      description: 'The same board, narrowed to one client',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'client': {'type': 'string'},
        },
        'required': ['client'],
      },
      handler: (args) async => _state(client: args['client'] as String?),
    );
  }

  CallToolResult _state({String? client}) {
    final rows = <Map<String, dynamic>>[];
    for (final d in _duties) {
      if (client != null && d.client != client) continue;
      final (date, shift) = _resolve(d);
      final days = date.difference(_today).inDays;
      rows.add({
        'client': d.client,
        'name': d.name,
        'due': _fmt(date),
        'days': days,
        // The rule, spelled out. A date without this is a number somebody typed.
        'rule': 'day ${d.dayOfMonth} of month ${d.monthOf}'
            '${shift.isEmpty ? '' : ' · $shift'}',
        'note': d.note,
        'state': days < 0
            ? 'overdue'
            : days <= 7
                ? 'due soon'
                : '',
      });
    }
    rows.sort((a, b) => (a['days'] as int).compareTo(b['days'] as int));

    final overdue = rows.where((r) => r['state'] == 'overdue').length;
    final soon = rows.where((r) => r['state'] == 'due soon').length;
    final shifted = rows.where((r) => (r['rule'] as String).contains('fell on')).length;

    return CallToolResult(content: [
      TextContent(
        text: jsonEncode({
          // Derived, not typed twice. Two places that must agree eventually
          // disagree.
          'today': _fmt(_today),
          'rows': rows,
          'rowCount': rows.length,
          // The rule the whole board runs by, printed once at the bottom: no
          // date is stored anywhere, so a statutory change moves every row.
          'filingRule': 'No date is stored · a statutory day that falls on a '
              'weekend moves to the next working day',
          'overdue': overdue,
          'soon': soon,
          'shifted': shifted,
          'headline': overdue > 0
              ? '$overdue overdue · $soon due within a week'
              : '$soon due within a week',
        }),
      )
    ]);
  }
}
