# Encoding: utf-8

require 'bundler/setup'
require 'github_api'
require 'github_api/pull_requests'
require 'pry'
require 'pp'


Label       = Struct.new :name, :color, :condition

# attr_reader :github, :owner, :repo, :pr_label, :ack_labels, :labels

@owner      = 'pitr-ch'
@repo       = 'kvizer'
@pr_label   = { name: 'PR', color: '207de5', condition: nil }
@ack_labels = [{ name: '✓', color: '009800', condition: /:shipit:|ACK/ },
               { name: '✘', color: 'e11d21', condition: /:x:|NACK/ }]
@labels     = @ack_labels + [@pr_label]
@github     = Github.new oauth_token: ENV['GITHUB_TOKEN'],
                         ssl:         { verify: false }

def run
  @github.issues.list(user: @owner, repo: @repo).each_page do |page|
    page.each do |i|
      next unless i.pull_request
      pull_request = i
      puts "processing ##{pull_request.number}"
      pr_comments    = @github.pull_requests.comments.list(@owner, @repo, request_id: pull_request.number)
      issue_comments = @github.issues.comments.list(@owner, @repo, issue_id: pull_request.number)
      comments       = [pr_comments, issue_comments]

      should_have_labels = [@pr_label[:name]] + @ack_labels.map do |label|
        matched = comments.any? do |comments|
          comments.to_enum(:each_page).any? do |page|
            page.any? { |comment| comment.body =~ label[:condition] }
          end
        end
        label[:name] if matched
      end.compact

      current_labels = pull_request.labels.map &:name
      difference     = (current_labels | should_have_labels) - (current_labels & should_have_labels)

      unless difference.empty?
        puts "replacing #{current_labels * ','} with #{should_have_labels * ','}"
        @github.issues.labels.replace @owner, @repo, pull_request.number.to_s, *should_have_labels
      end
    end
  end
end

def check_labels_exists
  @labels.each do |label|
    unless @github.issues.labels.list(user: @owner, repo: @repo).map(&:name).include? label[:name]
      puts "creating #{label[:name]}"
      @github.issues.labels.create user:  @owner,
                                   repo:  @repo,
                                   name:  label[:name],
                                   color: label[:color]
    end
  end
end

check_labels_exists

loop do
  begin
    puts '-- loop'
    run
    puts '-- done'
    $stdout.flush
    sleep 60*10
  rescue => e
    puts "(#{e.class}) #{e.message}\n#{e.backtrace.join("\n")}"
  end
end



