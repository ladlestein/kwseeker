#!/usr/bin/env ruby -w

require 'rubygems'
require 'bundler/setup'

require 'json'
require 'octokit'
require 'redis'
require 'jenkins_api_client'


github_token = ENV['KWSEEKER_GITHUB_AUTH_TOKEN']
repo = ENV['KWSEEKER_REPO'] || "joyent/node"
jenkins_server_ip = ENV['KWSEEKER_JENKINS_SERVER_IP'] || "dh"
jenkins_server_port = ENV['KWSEEKER_JENKINS_SERVER_PORT'] || 8082

redis = Redis.new

github = Octokit::Client.new(:access_token => github_token)
user = github.user
user.login

jenkins = JenkinsApi::Client.new(server_ip: jenkins_server_ip, server_port: jenkins_server_port)

#
# Find the next commit to analyze, or, if there's a command line argument, interpret it as the SHA for that commit.
#
if ! ARGV[0].nil?
  sha1 = ARGV[0]
else 
  puts "Searching for a commit candidate is not implemented yet."
  exit
end

#
# Ask Github for this commit's parents.
#
commit = github.commit(repo, sha1)
parents = commit.parents
if parents.length > 1 
  puts "SHA1 #{sha1} in repo #{repo} has #{parents.length} parents; more than one parent isn't supported yet."
  exit
end

parent_sha = parents[0].sha
puts "Its parent is #{parent_sha}"

#
# Run an analysis, using Jenkins, on the parent commit, and then on the commit itself.
#
jenkins.job.build("analyze", {sha1: parent_sha})
jenkins.job.build("analyze", {sha1: sha1})
