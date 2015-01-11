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

def issues client, repo

  cache = client.repository_issue_events repo
  next_relation = client.last_response.rels[:next] # do this before we fetch each issue, or else last_response will be changed.
  cache.each { |issue| yield issue }
  until next_relation.nil?
    next_url = next_relation.href
    $log.info "Fetching next page of issues from #{next_url}"
    cache = $github.get next_url
    next_relation = client.last_response.rels[:next] # do this before we fetch each issue, or else last_response will be changed.
    cache.each { |issue| yield issue }
  end

end

$log = Logger.new(STDOUT)

$github_token = ENV['KWSEEKER_GITHUB_AUTH_TOKEN'] || ARGV[0]
$github_repo = ENV['KWSEEKER_GITHUB_REPO'] || "ladlestein/seeker-test"
$jenkins_host = ENV['KWSEEKER_JENKINS_HOST'] || "localhost"
$jenkins_port = ENV['KWSEEKER_JENKINS_PORT'] || 3010
$jenkins_job_name = ENV['KWSEEKER_JENKINS_JOB_NAME'] || "analyze"
$kw_username = ENV['KWSEEKER_KW_USERNAME'] || "ledelstein"
$kw_host = ENV['KWSEEKER_KW_HOST'] || 'localhost'
$kw_project_name = ENV['KWSEEKER_KW_PROJECT_NAME'] || 'seeker-test'
$build_command = ENV['KWSEEKER_BUILD_COMMAND'] || 'make'
$prebuild_command = ENV['KWSEEKER_PREBUILD_COMMAND']
redis = Redis.new

$github = Octokit::Client.new(:access_token => $github_token)
user = $github.user
user.login

$jenkins = JenkinsApi::Client.new(server_ip: $jenkins_host, server_port: $jenkins_port)
kw_endpoint = "http://#{$kw_host}/review/api"
$klocwork = KlocworkApi::Client.new(kw_endpoint, $kw_username)

def analyze_deltas event

  $log.info "Analyzing deltas for issue #{event.issue.number} at #{event.issue.url} with commit #{event.issue.commit_id}"
  #
  # Ask Github for this commit's parents.
  #
  sha1 = event.commit_id
  commit = $github.commit($github_repo, sha1)
  parents = commit.parents

  if parents.length > 1 
    $log.warn "SHA1 #{sha1} in repo #{$github_repo} has #{parents.length} parents; more than one parent isn't supported yet."
  else
    parent_sha = parents[0].sha
    
    #
    # Enqueue analysis, using Jenkins, on the parent commit, and then on the commit itself.
    #
    $log.info "Queueing analyses of #{sha1} and its parent #{parent_sha}"
    $jenkins.job.build("analyze", {
                         branch_spec: parent_sha, 
                         kw_project_name: $kw_project_name, 
                         kw_build_name: "issue_#{event.id}_parent_#{parent_sha}",
                         github_repo: $github_repo,
                         build_command: $build_command,
                         prebuild_command: $prebuild_command
                       })
    $jenkins.job.build("analyze", {
                         branch_spec: sha1, 
                         kw_project_name: $kw_project_name, 
                         kw_build_name: "issue_#{event.id}_sha_#{sha1}",
                         github_repo: $github_repo,
                         build_command: $build_command,
                         prebuild_command: $prebuild_command
                       })
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

def create_or_update_job
  contents = File.read("job_template.xml")
  $log.info("read job template, contents: #{contents}")
  $log.info("creating/updating Jenkins job")
  $jenkins.job.create_or_update($jenkins_job_name, contents)
end

#
# Find all the events with commits, and run before-and-after KW analyses on each.
# Unless an event ID is specified on the command line, in which case, just analyze that event.
#
if ! ARGV[0].nil?
  puts "Analyzing a single event is not implemented yet."
else 
#  create_or_update_job
  $log.info "Fetching issues from beginning of repo #{$github_repo}"
  issues($github, $github_repo) { | issue | analyze_deltas( issue ) if ! issue.commit_id.nil? }
end


