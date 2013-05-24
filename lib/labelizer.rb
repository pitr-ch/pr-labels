# Encoding: utf-8

require 'bundler/setup'
require 'github_api'
require 'github_api/pull_requests'
require 'pry'
require 'pp'


class PRLabels
  class Label < Struct.new(:name, :color, :regexp)
  end

  attr_reader :github, :owner, :repo, :pr_label, :ack_labels, :labels

  def initialize(owner, repo, token, pr_label, ack_labels)
    @owner, @repo = owner, repo
    @pr_label     = pr_label
    @ack_labels   = ack_labels
    @labels       = ack_labels + [pr_label]
    @github       = Github.new oauth_token: token,
                               ssl:         { verify: false }
  end

  def run
    pull_requests { |pr| check_labels pr }
  end

  def check_labels_exists
    labels.each do |label|
      unless github.issues.labels.list(user: owner, repo: repo).map(&:name).include? label.name
        puts "creating #{label.name}"
        github.issues.labels.create user:  owner,
                                    repo:  repo,
                                    name:  label.name,
                                    color: label.color
      end
    end
  end

  private

  def check_labels(pull_request)
    pr_comments    = github.pull_requests.comments.list(owner, repo, request_id: pull_request.number)
    issue_comments = github.issues.comments.list(owner, repo, issue_id: pull_request.number)

    should_have_labels = [pr_label.name] + ack_labels.map do |label|
      test = -> comment { comment.body =~ label.regexp }
      label.name if pr_comments.any?(&test) || issue_comments.any?(&test)
    end.compact

    current_labels = pull_request.labels.map &:name
    difference     = (current_labels | should_have_labels) - (current_labels & should_have_labels)

    unless difference.empty?
      puts "replacing #{current_labels * ','} with #{should_have_labels * ','} in #{pull_request.number}"
      github.issues.labels.replace owner, repo, pull_request.number.to_s, *should_have_labels
    end
  end

  def issues(&block)
    github.issues.list user: owner, repo: repo, &block
  end

  def pull_requests(&block)
    issues { |i| block.call i if i.pull_request }
  end
end

pr_labels = PRLabels.new 'Katello',
                         'katello',
                         ENV['GITHUB_TOKEN'],
                         PRLabels::Label.new('PR', '207de5', nil),
                         [PRLabels::Label.new('✓', '009800', /:shipit:|ACK/),
                          PRLabels::Label.new('✘', 'e11d21', /:x:|NACK/)
                         ]
pr_labels.check_labels_exists

loop do
  begin
    puts '-- loop'
    pr_labels.run
    sleep 60*10
    puts '-- done'
  rescue => e
    puts "(#{e.class}) #{e.message}\n#{e.backtrace.join("\n")}"
  end
end



