#!/usr/bin/env ruby -w

require 'rubygems'
require 'bundler/setup'

require 'logger'

require 'json'
require 'octokit'
require 'redis'
require 'jenkins_api_client'
require 'faraday'
require_relative 'klocwork_api'

$log = Logger.new("/var/log/kwseeker/work.log")

$github_token = ENV['KWSEEKER_GITHUB_AUTH_TOKEN']
$repo = ENV['KWSEEKER_REPO'] || "ladlestein/seeker-test"
$jenkins_server_ip = ENV['KWSEEKER_JENKINS_SERVER_IP'] || "localhost"
$jenkins_server_port = ENV['KWSEEKER_JENKINS_SERVER_PORT'] || 3010
$kw_project_name = ENV['KWSEEKER_KLOCWORK_PROJECT_NAME'] || "seeker-test"
$kw_username = ENV['KWSEEKER_KLOCWORK_USERNAME'] || "ledelstein"
$kw_api_endpoint = ENV['KWSEEKER_KLOCWORK_API_ENDPOINT'] || 'http://localhost:3030/review/api'
$kw_project_name = ENV['KWSEEKER_PROJECT_NAME'] || "analyze"

redis = Redis.new

$github = Octokit::Client.new(:access_token => $github_token)
user = $github.user
user.login

$jenkins = JenkinsApi::Client.new(server_ip: $jenkins_server_ip, server_port: $jenkins_server_port)
$klocwork = KlocworkApi::Client.new($kw_api_endpoint, $kw_username)

def each_event_with_commit
  $log.info "Fetching issues from beginning of repo #{$repo}"
  events = $github.repository_issue_events $repo
  n = events.length

  begin
    events_with_commit = events.select {|e| ! e.commit_id.nil?}
    events_with_commit.each do |e| 
      $log.info "Found issue #{e.id} with commit #{e.commit_id}"
      yield e
    end
    unless $github.last_response.rels[:next].nil?
      next_url = $github.last_response.rels[:next].href
      $log.info "Fetching next page of issues from #{next_url}"
      events = $github.get next_url
      n += events.length
    end
  end until $github.last_response.rels[:next].nil?
end

def analyze_deltas event
  #
  # Ask Github for this commit's parents.
  #
  sha1 = event.commit_id
  commit = $github.commit($repo, sha1)
  parents = commit.parents

  if parents.length > 1 
    $log.warning "SHA1 #{sha1} in repo #{$repo} has #{parents.length} parents; more than one parent isn't supported yet."
  else
    parent_sha = parents[0].sha
    
    #
    # Enqueue analysis, using Jenkins, on the parent commit, and then on the commit itself.
    #
    $log.info "Queueing analyses of #{sha1} and its parent #{parent_sha}"
    $jenkins.job.build("analyze", {branch_spec: parent_sha, build_name: "issue_#{event.id}_parent_#{parent_sha}"})
    $jenkins.job.build("analyze", {branch_spec: sha1, build_name: "issue_#{event.id}_sha_#{sha1}"})

    #
    # Look for issues that were fixed by the second build.
    #
    #name = $klocwork.getLatestBuildName($kw_project_name)
    #query = "state:FIXED build:#{build_name}"
    #results = $klocwork.search(name, query)
    #if results.length > 0
    #  $log.info "There are #{results.length} fixed issues between builds for #{parent_sha} and #{sha1}"
    #else
    #  $log.info "No fixed issues found between builds for #{parent_sha} and #{sha1}"
    #end
  end
end

#
# Find all the events with commits, and run before-and-after KW analyses on each.
# Unless an event ID is specified on the command line, in which case, just analyze that event.
#
if ! ARGV[0].nil?
  puts "Analyzing a single event is not implemented yet."
else 
  each_event_with_commit { |event| analyze_deltas event }
end


