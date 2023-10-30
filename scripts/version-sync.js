#!/usr/bin/env node

const fs = require('fs');
const {version} = require('../package.json');

function main() {

    const filePath = './plugin.xml';
    let pluginData = fs.readFileSync(filePath).toString();

    pluginData = pluginData.replace(/(<plugin.*version=")([^"]+)(".*)/, `$1${version}$3`);
    fs.writeFileSync(filePath, pluginData);
}

main();