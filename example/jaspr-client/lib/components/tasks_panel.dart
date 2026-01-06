/// Tasks panel component.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:mcp_dart/mcp_dart.dart';

class TasksPanel extends StatelessComponent {
  final List<Task> tasks;
  final Function(String taskId) onCancelTask;
  final Function() onRefresh;

  const TasksPanel({
    required this.tasks,
    required this.onCancelTask,
    required this.onRefresh,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return section(classes: 'panel tasks-panel', [
      div(classes: 'panel-header', [
        h2([Component.text('Tasks')]),
        button(
          classes: 'btn btn-small btn-secondary',
          onClick: onRefresh,
          [Component.text('Refresh')],
        ),
      ]),
      if (tasks.isEmpty)
        div(classes: 'empty-state', [
          p([Component.text('No tasks available.')]),
        ])
      else
        div(classes: 'tasks-list', [
          for (final task in tasks) _buildTaskItem(task),
        ]),
    ]);
  }

  Component _buildTaskItem(Task task) {
    final isTerminal = task.status.isTerminal;
    return div(classes: 'tool-card', [
      div(classes: 'tool-header', [
        h3([Component.text('Task: ${task.taskId}')]),
        if (!isTerminal)
          button(
            classes: 'btn btn-small btn-secondary',
            onClick: () => onCancelTask(task.taskId),
            [Component.text('Cancel')],
          ),
      ]),
      div([
        span(classes: 'tool-args', [Component.text('Status: ${task.status.name}')]),
        if (task.createdAt != null)
          span(
            classes: 'tool-args',
            attributes: {'style': 'margin-left: 0.5rem'},
            [Component.text('Created: ${task.createdAt}')],
          ),
      ]),
      if (task.statusMessage != null)
        p(
          classes: 'tool-description',
          attributes: {'style': 'margin-top: 0.5rem'},
          [Component.text(task.statusMessage!)],
        ),
    ]);
  }
}
