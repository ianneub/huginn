require 'rails_helper'

describe Agents::EcsAgent, :vcr do
  before do
    @valid_params = {
                      cluster: 'testing',
                      wait_for_task: true,
                      container_definitions: [
                        {
                          name: 'worker',
                          image: 'ubuntu:14.04',
                          memory: 512,
                          essential: true,
                          command: ['/bin/true'],
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

    @checker = Agents::EcsAgent.new(:name => "somename", :options => @valid_params)
    @checker.user = users(:jane)
    @checker.save!
  end

  describe "#check" do
    it "should check that initial run creates an event" do
      expect { @checker.check }.to change { Event.count }.by(1)
    end
  end
end
