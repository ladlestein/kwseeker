#!/usr/bin/env ruby -w

require 'rubygems'
require 'bundler/setup'

require 'logger'

require 'jenkins_api_client'
require 'faraday'
require 'rugged'

require_relative 'klocwork_api'

$log = Logger.new(STDOUT)

$github_repo = ENV['KWSEEKER_GITHUB_REPO'] || "ladlestein/seeker-test"
$jenkins_host = ENV['KWSEEKER_JENKINS_HOST'] || "localhost"
$jenkins_port = ENV['KWSEEKER_JENKINS_PORT'] || 3010
$jenkins_job_name = ENV['KWSEEKER_JENKINS_JOB_NAME'] || "node"
$kw_username = ENV['KWSEEKER_KW_USERNAME'] || "ledelstein"
$kw_host = ENV['KWSEEKER_KW_HOST'] || 'localhost'
$kw_project_name = ENV['KWSEEKER_KW_PROJECT_NAME'] || 'seeker-test'
$build_command = ENV['KWSEEKER_BUILD_COMMAND'] || 'make'
$prebuild_command = ENV['KWSEEKER_PREBUILD_COMMAND'] || "./configure --without-ssl"

$jenkins = JenkinsApi::Client.new(server_ip: $jenkins_host, server_port: $jenkins_port)
kw_endpoint = "http://#{$kw_host}/review/api"
$klocwork = KlocworkApi::Client.new(kw_endpoint, $kw_username)

$first_build = true

def analyze_deltas commit, previous_commit, issue_number
  sha1 = commit.oid
  parent_sha = previous_commit.oid
  $log.info "Analyzing commit #{sha1}, succeeding commit #{parent_sha} which says it closes #{issue_number}"
  
  #
  # Enqueue analysis, using Jenkins, on the parent commit, and then on the commit itself.
  #
  $jenkins.job.build($jenkins_job_name, {
                       branch_spec: parent_sha, 
                       kw_project_name: $kw_project_name, 
                       kw_build_name: "issue_#{issue_number}_parent_#{parent_sha}",
                       github_repo: $github_repo,
                       build_command: $build_command,
                       prebuild_command: $prebuild_command,
                       incremental: if $first_build then '--force' else '--incremental' end
                     })
  $first_build = false
  $jenkins.job.build($jenkins_job_name, {
                       branch_spec: sha1, 
                       kw_project_name: $kw_project_name, 
                       kw_build_name: "issue_#{issue_number}_sha_#{sha1}",
                       github_repo: $github_repo,
                       build_command: $build_command,
                       prebuild_command: $prebuild_command,
                       incremental: '--incremental'
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


def closes_issue(commit)
  pattern = /(?:fix|fixes|fixed|close|closes|closed|resolve|resolves|resolved) +#([0-9]+)/i
  commit.message.scan(pattern).join
end

def create_or_update_job
  contents = File.read("job_template.xml")
  $log.info("read job template, contents: #{contents}")
  $log.info("creating/updating Jenkins job")
  $jenkins.job.create_or_update($jenkins_job_name, contents)
end

def commits(path)
  $log.info "creating repo for path = #{path}"
  repo = Rugged::Repository.new(path)
  walker = Rugged::Walker.new(repo)
  walker.push("master")
  walker.sorting(Rugged::SORT_DATE)
  
  # It would be nice to just do a yield here, but alas, we need to reverse the collection. 
  # If it were a huge collection that'd be a problem, but I doubt there will be a repo that has enough 
  # commits to be called "huge".
  coll = walker.map {|x| x}
  coll.reverse
end

#
# Find all the commits that claim to fix something ("Fixes #1234"). 
# Queue up an analysis on them and their precedessors.
#
local_repo_path = ARGV[0] || "."
starting_commit = ARGV[1]
previous_commit = ARGV[2]

create_or_update_job

commits = commits(local_repo_path)
commits = commits.drop_while {|commit| commit.oid != starting_commit} unless starting_commit.nil?
commits.each { | commit | 
  $log.info "looking at #{commit} with subject #{commit.message}"
  issue_number = closes_issue(commit)
  analyze_deltas(commit, previous_commit, issue_number) unless issue_number.empty?
  previous_commit = commit
}
    
