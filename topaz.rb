at_exit { shutdown() }

require 'rubygems'
require 'sinatra'	# our web framework
require 'open4'		# so we can get pid, stdin, stdout, stderr from Topaz
require 'json'		# our response to AJAX requests

# requests might come from multiple hosts (e.g., behind a corporate firewall)
configure do
    disable :protection
end


$processes = Hash.new			# collection of processes
set :bind, '0.0.0.0'			# listen on all interfaces, not just localhost
set :public_folder, 'public'	# where to get static docs
ENV['GEMSTONE'] = Dir.pwd		# so Topaz can find help file

# background job to expire orphan sessions
th = Thread.new do
	while true do
		oneMinuteAgo = Time.now - 60
		$processes.delete_if { | pid, process |
			lastHeartbeat = process[:time]
			if (lastHeartbeat && lastHeartbeat < oneMinuteAgo)
				stopSession(pid, process)
				true
			else
				false
			end
		}
		sleep(30)
	end
end


get '/' do
    redirect '/topaz.html'
end

get '/break' do
	process = process(params)
	if (process == nil) then return { :error => 'process not found' }.to_json end
	Process.kill('INT', process[:pid].to_i)
	update(process)
end

post '/command' do
	string = params[:command]
	process = process(params)
	if (process == nil) then return { :error => 'process not found' }.to_json end
	process[:stdin].puts string
	update(process)
end

get '/heartbeat' do
	process = process(params)
	time = Time.now
	if (process)
		process[:time] = time
	end
	{ :heartbeat => time }.to_json
end

get '/start' do
	process = Hash.new
	pid, stdin, stdout, stderr = Open4::popen4 './topaz'
	pid = pid.to_s
	process[:pid] = pid
	process[:stdin] = stdin
	process[:stdout] = stdout
	process[:stderr] = stderr
	process[:time] = Time.now
	process[:requestId] = params[:i]
	$processes[pid] = process
	STDOUT.write "Topaz started with pid #{ pid }\n"
	update(process)
end

get '/stack' do
	process = process(params)
	if (process == nil) then return { :error => 'process not found'}.to_json end
	Process.kill('USR1', process[:pid].to_i)
	update(process)
end

get '/unload' do
	process = process(params)
	if (process)
		pid = process[:pid]
		stopSession(pid, process)
		$processes.delete(pid)
	end
	''
end

get '/update' do
	process = process(params)
	if (process == nil) then return { :error => 'process not found'}.to_json end
	update(process)
end


def isActive(pid)
	begin
		return Process.waitpid(pid.to_i, Process::WNOHANG) == nil
	rescue Errno::ECHILD
		return false
	end
end

def process(params) 
	pid = params[:pid]
	if (pid && $processes.has_key?(pid))
		if (isActive(pid))
			process = $processes[pid]
			process[:requestId] = params[:i]
			return process
		else
			STDOUT.write "PID <#{ pid }> found but is not active\n"
		end
	else
		STDOUT.write "PID <#{ pid }> not found in #{ $processes.keys.to_s }\n"		
	end
	return nil
end

def shutdown
	$processes.each do | pid, process |
		stopSession(pid, process)
	end
end

def stopSession(pid, process)
	if (isActive(pid))
		STDOUT.write "closing stdin for Topaz PID #{ pid }\n"
		process[:stdin].close
		sleep(1)
	end
	if (isActive(pid))
		STDOUT.write "sending TERM to Topaz PID #{ pid }\n"
		Process.kill('TERM', pid.to_i)
		sleep(1)
	end
	if (isActive(pid))
		STDOUT.write "sending KILL to Topaz PID #{ pid }\n"
		Process.kill('KILL', pid.to_i)
	end
end

#	We will wait up to 30 seconds for something to return.
#	As long as something is coming, we will continue to wait.
#	This will "chunk" the output to reduce network traffic.
#	If another request comes in, we will send what we have now.
def update(process)
	$currentRequestId = process[:requestId]
	myRequestId = $currentRequestId
	stderr = String.new
	stdout = String.new
	sleep(0.01)
	haveSomethingToReturn = false
	for i in 1..300
		gotSomethingRecently = false
		mySize = process[:stderr].stat.size
		if (0 < mySize)
			stderr << process[:stderr].readpartial(mySize)
			haveSomethingToReturn = true
			gotSomethingRecently = true
		end
		mySize = process[:stdout].stat.size
		if (0 < mySize) 
			stdout << process[:stdout].readpartial(mySize)
			haveSomethingToReturn = true
			gotSomethingRecently = true
		end
		#	Is there another request that can take the remaining output?
		if (myRequestId != $currentRequestId)
			break
		end
		if (haveSomethingToReturn && !gotSomethingRecently)
			break
		end
		sleep(0.1)
	end
	response = { :pid => process[:pid], :i => myRequestId }
	if (!stderr.empty?) 
		response[:stderr] = stderr
	end
	if (!stdout.empty?)
		response[:stdout] = stdout
	end
	return response.to_json
end
