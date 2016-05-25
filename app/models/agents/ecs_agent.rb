module Agents
  class EcsAgent < Agent

    description <<-MD
      This agent will let you run tasks in ECS. It will create a Task Definition in ECS based on your configuration and will run the task in the cluster indicated.

      The `cluster` setting determines which cluster to run the task in.

      The `container_definitions` setting is an Array of [Container Definition](http://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html) objects.

      The `wait_for_task` setting will determine if this agent should wait for a task to complete before generating an event. It will also change what kind of event is emitted.
    MD

    default_schedule "every_1d"

    event_description <<-MD
      When wait_for_task is set to true, events contain a JSON representation of an ECS Task:

        {
          "task_id": "...",
          "image": "...",
          "containers": [
            {
              "name": "...",
              "last_status": "...",
              "exit_code": 0
            }
          ]
        }

      When wait_for_task is set to false, events will look like:

        {
          "cluster": "...",
          "task_id": "..."
        }
    MD

    cannot_receive_events!

    def default_options
      { 
        cluster: 'default',
        wait_for_task: true,
        container_definitions: [
          {
            name: 'worker',
            image: 'ubuntu:14.04',
            memory: 512,
            essential: true,
            environment: [
              {
                name: "ASDF",
                value: 'true'
              }
            ]
          }
        ],
        expected_update_period_in_days: 1
      }
    end

    def validate_options
      errors.add(:base, 'expected_update_period_in_days is required') unless options['expected_update_period_in_days'].present?
      errors.add(:base, 'cluster is required') unless options['cluster'].present?
      errors.add(:base, 'container_definitions is required') unless options['container_definitions'].present?
      errors.add(:base, 'wait_for_task is required') unless options['wait_for_task'].present?
      if options['container_definitions'].present?
        options['container_definitions'].each do |cd|
          errors.add(:container_definitions, 'name is required') unless cd.include?('name')
          errors.add(:container_definitions, 'image is required') unless cd.include?('image')
        end
      end
    end

    def working?
      event_created_within?(interpolated['expected_update_period_in_days']) && !recent_error_logs?
    end

    def check
      # create or update ecs task definition
      name = "HuginnAgentsEcsAgent-#{self.id}"
      revision = create_task_definition(family: name, container_definitions: interpolated['container_definitions'])
      
      # run task
      arn = run_task(cluster: interpolated['cluster'], task_definition: name, revision: revision)

      if interpolated['wait_for_task']
        # wait for task to complete
        resp = get_ecs_status(cluster: interpolated['cluster'], task: arn)
        # emit completed task event
        create_event payload: resp.tasks[0].to_json
      else
        # emit run start event
        create_event payload: {cluster: interpolated['cluster'], task_id: arn}
      end
    end

    private
    def get_ecs_status(cluster:, task:)
      ecs = Aws::ECS::Client.new

      # wait for task to stop
      ecs.wait_until(:tasks_stopped, cluster: cluster, tasks: [task]) do |w|
        w.max_attempts = nil
        w.delay = 10
      end

      # get task detail
      ecs.describe_tasks({
        cluster: cluster,
        tasks: [task]
      })
    end

    def create_task_definition(family:, container_definitions:)
      ecs = Aws::ECS::Client.new
      task_def = {family: family, container_definitions: container_definitions}
      resp = ecs.register_task_definition(task_def)
      resp.task_definition.revision
    end

    def run_task(cluster:, task_definition:, revision:)
      ecs = Aws::ECS::Client.new
      resp = ecs.run_task({
        cluster: cluster,
        task_definition: "#{task_definition}:#{revision}",
        count: 1,
        started_by: "HuginEcsAgent-#{self.id}"
      })
      resp.tasks[0].task_arn
    end
  end
end
