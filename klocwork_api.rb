module KlocworkApi

  class Client
    
    def initialize(api_endpoint, username)
      @conn = Faraday.new(:url => api_endpoint)
      @username = username
    end

    def getLatestBuildName(project_name)
      response = @conn.post '', {action: 'builds', user: @username, project: project_name}
      builds = response.body.lines.map { |line| JSON.parse line }
      sorted = builds.sort { |a,b| a['date'] <=> b['date'] }
      sorted.last['name']
    end

    def search(project_name, query)
      response = @conn.post '', {action: 'search', user: @username, project: project_name, query: query}
      issues = response.body.lines.map { |line| JSON.parse line }
      issues
    end
    
  end

end
