require "test_helper"
require "fugit"

# A mistake in the schedule file does not fail anything. The scheduler skips
# what it cannot use, the table stops growing, and a demo with no new entries
# looks exactly like a community that stopped posting — so what the file says
# is read here the way Solid Queue reads it.
#
# It is read rather than handed to SolidQueue::RecurringTask because that model
# needs the queue tables, and those live in a database only production has.
class RecurringScheduleTest < ActiveSupport::TestCase
  SCHEDULE = Rails.application.config_for(:recurring, env: "production")

  test "each source is fetched daily, in the zone this demo is given in" do
    tasks = SCHEDULE.select { |_, task| task[:class].to_s.start_with?("Fetch") }

    assert_equal 3, tasks.size

    tasks.each_value do |task|
      assert task[:class].safe_constantize, "#{task[:class]} is scheduled but does not exist"

      cron = Fugit.parse(task[:schedule], multi: :fail)
      assert_instance_of Fugit::Cron, cron, "#{task[:schedule].inspect} is not a schedule Solid Queue accepts"
      # Left unnamed, the zone defaults to UTC and the fetch lands mid-afternoon.
      assert_equal "Asia/Taipei", cron.zone
      assert_equal [ 5 ], cron.hours
    end
  end
end
