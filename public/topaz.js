
var input, output, pid, prompt;
var counter = 0;

function heartbeat() {
	if (pid) {
		get('heartbeat');
	}
}

function get(path) {
	string = '/' + path + '?pid=' + pid + '&i=' + counter++;
//	console.log('GET ' + string);
	var request = new XMLHttpRequest();
	request.onreadystatechange=readyStateChanged;
	request.open('GET', string, true);
	request.send();
	input.focus();
}

function readyStateChanged(progressEvent) {
	if (this.readyState != 4) return;
	if (this.status != 200) return;
	var response = JSON.parse(progressEvent.target.responseText);
//	console.log(response);
	if (response.heartbeat)	return;
	if (response.error)		return alert(response.error);
	if (response.stderr) {
		if (output.lastChild && output.lastChild.className == 'newLine') {
			output.removeChild(output.lastChild);
			console.log('removed newLine to add stderr');
		}
		var pre  = document.createElement('pre');
		var code = document.createElement('code');
		var text = document.createTextNode( response.stderr );
		code.appendChild(text);
		pre.appendChild(code);
		code.className = 'error';
		output.appendChild(pre);
	}
	var string = response.stdout;
	if (string) {
		var gotPrompts = false;
		if (output.lastChild.className == 'newLine') {
			output.removeChild(output.lastChild);
		}
		// strip duplicate prompt from first line
		if (prompt && 0 === string.indexOf(prompt)) {
			string = string.substr(prompt.length);
		}
		var index = string.lastIndexOf("\n");
		var lastLine;
		if (index == -1) {
			lastLine = string;
			string = '';
		} else {
			lastLine = string.substring(index + 1);
			string = string.substring(0,index + 1);
		}
		var pre  = document.createElement('pre');
		var code = document.createElement('code');
		var text = document.createTextNode(string);
		code.appendChild(text);
		pre.appendChild(code);
		output.appendChild(pre);
		code = document.createElement('code');
		text = document.createTextNode(lastLine);
		code.appendChild(text);
		pre.appendChild(code);
		output.appendChild(pre);
		console.log(code.offsetWidth);
		input.style.left = code.offsetWidth + 20 + 'px';
		var prompts = lastLine.match(/topaz ?\d*> $/);
		if (prompts) {
			prompt = prompts[0];
			gotPrompts = true;
		} else {
			prompts = string.match(/Topic\? $/);
			if (prompts) {
				console.log(prompts);
				prompt = prompts[0];
				gotPrompts = true;
			}
		}
		if (!gotPrompts) {
			get('update');
		}
	}
	output.scrollTop = output.scrollHeight;
	if (typeof pid == 'undefined') {
		pid = response.pid;
	} else {
		if (pid != response.pid) {
			alert('Request was for PID ' + pid + ', but response was for PID ' + response.pid + '!');
		}
	}
}

function exitTopaz() {
	get('unload');
	return nil;		// or 'Are you sure?';
}

function onload() {
	input = document.getElementById('input');
	output = document.getElementById('output');
	setInterval(heartbeat, 20000);
	input.focus();
	window.onbeforeunload = exitTopaz;
	get('start');
}

//	add command to end of existing last line (typically a prompt)
//	then add a blank line
function submitCommand() {
	var command = input.value;
	var params = 'pid=' + pid + '&i=' + counter++ + '&command=' + encodeURIComponent(command);
	var request = new XMLHttpRequest();
	request.onreadystatechange=readyStateChanged;
	request.open('POST', '/command', true);
	request.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
	request.send(params);
	input.value = '';

	var element = output.lastChild.lastChild;
	var string = element.innerHTML;
	if (element.parentNode.className == 'newLine') {
		string = '';
	}
	element.innerHTML = string + '<span class="command">' + command + '</span>';

	var pre  = document.createElement('pre');
	var code = document.createElement('code');
	var text = document.createTextNode( ' ' );
	code.appendChild(text);
	pre.appendChild(code);
	pre.className = 'newLine';
	output.appendChild(pre);
	input.style.left = '20px';
}
