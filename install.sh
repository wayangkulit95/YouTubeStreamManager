#!/bin/bash

# Update package list
sudo apt update

# Install Node.js and npm
sudo apt install -y nodejs npm

# Install FFmpeg
sudo apt install -y ffmpeg

# Install yt-dlp
sudo apt install -y python3-pip
pip3 install -U yt-dlp

# Create project directory
mkdir -p ~/youtube-streamer
cd ~/youtube-streamer

# Create directories for streams and views
mkdir -p streams
mkdir -p views

# Create index.html file
cat <<EOL > views/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>YouTube Streamer</title>
</head>
<body>
    <h1>YouTube Live Stream to M3U8</h1>
    <form action="/add-stream" method="POST">
        <input type="text" name="videoId" placeholder="YouTube Video ID" required>
        <input type="text" name="streamName" placeholder="Stream Name (optional)">
        <button type="submit">Add Stream</button>
    </form>
    <h2>Active Streams:</h2>
    <ul id="streamList"></ul>
    <script>
        fetch('/streams').then(response => response.json()).then(data => {
            const streamList = document.getElementById('streamList');
            data.forEach(stream => {
                const li = document.createElement('li');
                li.innerHTML = \`<strong>\${stream.name}</strong> - <a href="/streams/\${stream.name}/stream.m3u8">M3U8 Link</a>
                <form action="/remove-stream" method="POST" style="display:inline;">
                    <input type="hidden" name="streamName" value="\${stream.name}">
                    <button type="submit">Remove</button>
                </form>\`;
                streamList.appendChild(li);
            });
        });
    </script>
</body>
</html>
EOL

# Create server.js file
cat <<EOL > server.js
const express = require('express');
const { exec } = require('child_process');
const path = require('path');
const bodyParser = require('body-parser');
const fs = require('fs');
const app = express();
const PORT = 80; // Change to 80 for HTTP

app.use(bodyParser.urlencoded({ extended: true }));
app.use(express.static('public'));

let streams = [];

// Route for the main page
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'views', 'index.html'));
});

// Route to add a new stream
app.post('/add-stream', (req, res) => {
    const videoId = req.body.videoId;
    const streamName = req.body.streamName || videoId;
    const m3u8File = path.join(__dirname, 'streams', \`\${streamName}/stream.m3u8\`);

    if (!fs.existsSync(path.dirname(m3u8File))) {
        fs.mkdirSync(path.dirname(m3u8File), { recursive: true });
    }

    // Command to fetch the stream URL using yt-dlp
    const command = \`yt-dlp --cookies cookies.txt -f "b" -g "https://www.youtube.com/watch?v=\${videoId}"\`;

    exec(command, (error, stdout, stderr) => {
        if (error) {
            console.error(\`Error fetching stream URL: \${error.message}\`);
            console.error(\`stderr: \${stderr}\`);
            return res.status(500).send('Error fetching stream URL.');
        }

        const streamUrl = stdout.trim();
        if (!streamUrl) {
            console.error('Stream URL is empty.');
            return res.status(500).send('Error: Stream URL is empty.');
        }

        // Start FFmpeg process to convert to M3U8
        const ffmpegCommand = \`ffmpeg -re -i "\${streamUrl}" -c:v copy -c:a copy -f hls -hls_time 10 -hls_list_size 0 -hls_flags delete_segments "\${m3u8File}"\`;
        
        const ffmpegProcess = exec(ffmpegCommand, (ffmpegError, ffmpegStdout, ffmpegStderr) => {
            if (ffmpegError) {
                console.error(\`FFmpeg error: \${ffmpegError.message}\`);
                return res.status(500).send('Error processing stream.');
            }
            console.log(\`FFmpeg output: \${ffmpegStdout}\`);
            streams.push({ name: streamName, m3u8File });
            res.redirect('/');
        });

        ffmpegProcess.stdout.on('data', (data) => console.log(\`FFmpeg: \${data}\`));
        ffmpegProcess.stderr.on('data', (data) => console.error(\`FFmpeg Error: \${data}\`));
    });
});

// Route to list streams
app.get('/streams', (req, res) => {
    res.json(streams);
});

// Route to remove a stream
app.post('/remove-stream', (req, res) => {
    const streamName = req.body.streamName;
    const streamIndex = streams.findIndex(stream => stream.name === streamName);

    if (streamIndex >= 0) {
        streams.splice(streamIndex, 1);
        const streamPath = path.join(__dirname, 'streams', streamName);
        fs.rm(streamPath, { recursive: true, force: true }, (err) => {
            if (err) {
                console.error(\`Failed to delete stream: \${err}\`);
            }
            res.redirect('/');
        });
    } else {
        res.status(404).send('Stream not found.');
    }
});

// Route to serve M3U8 file
app.get('/streams/:name/stream.m3u8', (req, res) => {
    const streamName = req.params.name;
    const m3u8File = path.join(__dirname, 'streams', streamName, 'stream.m3u8');

    res.sendFile(m3u8File, (err) => {
        if (err) {
            console.error(\`Error sending M3U8 file: \${err}\`);
            res.status(err.status).end();
        }
    });
});

// Start server
app.listen(PORT, () => {
    console.log(\`Server is running on http://localhost:\${PORT}\`);
});
EOL

# Create a cookies.txt file (you need to manually add cookies)
touch cookies.txt

# Install dependencies
npm init -y
npm install express body-parser

echo "Setup complete! Please update cookies.txt with your YouTube session cookies."
