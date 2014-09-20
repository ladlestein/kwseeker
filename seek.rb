require 'rubygems'
require 'bundler/setup'

require 'json'
require 'octokit'
require 'redis'


redis = Redis.new

client = Octokit::Client.new(:access_token => ENV['KWSEEKER_GITHUB_AUTH_TOKEN'])
user = client.user
user.login


events = client.repository_issue_events("joyent/node")
n = events.length

until client.last_response.rels[:next].nil?
  puts client.last_response.rels[:next].href
  has_commit = events.select {|e| ! e.commit_id.nil?}
  has_commit.each {|e| redis.set(e.id, e.commit_id)}
  events = client.get(client.last_response.rels[:next].href)
  n += events.length
end

puts n

