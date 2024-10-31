#!/bin/bash

# Update package lists
echo "Updating package lists..."
sudo apt update

# Install FFmpeg
echo "Installing FFmpeg..."
sudo apt install -y ffmpeg

# Install Node.js and npm
echo "Installing Node.js and npm..."
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt install -y nodejs

# Create application directory
APP_DIR=~/youtube-streamer
echo "Creating application directory at $APP_DIR..."
mkdir -p $APP_DIR
cd $APP_DIR

# Initialize Node.js project
echo "Initializing Node.js project..."
npm init -y

# Install required Node.js packages
echo "Installing required Node.js packages..."
npm install express body-parser ejs fs child_process

# Create server.js file
cat << 'EOF' > server.js
const express = require('express');
const bodyParser = require('body-parser');
const fs = require('fs');
const { exec } = require('child_process');
const path = require('path');

const app = express();
const PORT = 80; // Change to port 80

// Middleware
app.use(bodyParser.urlencoded({ extended: true }));
app.use(express.static('public'));
app.set('view engine', 'ejs');

// Data structure to hold stream information
let streams = [];

// Render the main page
app.get('/', (req, res) => {
    res.render('index', { streams });
});

// Add a new stream
app.post('/add-stream', (req, res) => {
    const videoId = req.body.videoId;
    const streamName = req.body.streamName;

    if (videoId && streamName) {
        const streamDir = path.join(__dirname, 'streams', streamName);
        const m3u8File = path.join(streamDir, 'stream.m3u8');

        // Create a directory for the stream
        fs.mkdirSync(streamDir, { recursive: true });

        // FFmpeg command to capture YouTube stream
        const command = `ffmpeg -i "https://www.youtube.com/watch?v=${videoId}" -c:v copy -c:a copy -f hls -hls_time 10 -hls_list_size 0 -hls_flags delete_segments "${m3u8File}"`;

        // Start capturing the stream
        exec(command, { cwd: streamDir }, (error) => {
            if (error) {
                console.error(`Error capturing stream: ${error.message}`);
                return res.status(500).send('Error capturing stream');
            }
        });

        streams.push({ name: streamName, videoId, m3u8File });
        res.redirect('/');
    } else {
        res.status(400).send('Missing video ID or stream name');
    }
});

// Remove a stream
app.post('/remove-stream', (req, res) => {
    const streamName = req.body.streamName;
    const streamDir = path.join(__dirname, 'streams', streamName);

    if (fs.existsSync(streamDir)) {
        fs.rmdirSync(streamDir, { recursive: true });
        streams = streams.filter(stream => stream.name !== streamName);
        res.redirect('/');
    } else {
        res.status(404).send('Stream not found');
    }
});

// Start the server
app.listen(PORT, () => {
    console.log(`Server is running on http://localhost:${PORT}`);
});
EOF

# Create views directory
mkdir views

# Create index.ejs file
cat << 'EOF' > views/index.ejs
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>YouTube Stream Manager</title>
</head>
<body>
    <h1>YouTube Stream Manager</h1>
    <form action="/add-stream" method="POST">
        <input type="text" name="videoId" placeholder="YouTube Video ID" required>
        <input type="text" name="streamName" placeholder="Stream Name" required>
        <button type="submit">Add Stream</button>
    </form>
    <h2>Active Streams</h2>
    <ul>
        <% streams.forEach(stream => { %>
            <li>
                <strong><%= stream.name %></strong>
                <button onclick="removeStream('<%= stream.name %>')">Remove</button>
                <br>
                <a href="http://<%= req.headers.host %>/streams/<%= stream.name %>/stream.m3u8">M3U8 Link</a>
            </li>
        <% }); %>
    </ul>

    <script>
        function removeStream(streamName) {
            fetch('/remove-stream', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: new URLSearchParams({ streamName }),
            }).then(() => location.reload());
        }
    </script>
</body>
</html>
EOF

# Create streams directory
mkdir streams

# Make the script executable
chmod +x install.sh

echo "Installation completed. You can now start the server with 'sudo node server.js' in the $APP_DIR directory."
