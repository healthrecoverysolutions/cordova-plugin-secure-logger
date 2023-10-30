#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function stripDuplicateImports(sourceFilePath) {
    console.log(`stripping duplicate imports for ${sourceFilePath}`);
    const data = fs.readFileSync(sourceFilePath).toString();
    const updated = data.replace(/import Cordova[\n\r\f]+import Cordova/, 'import Cordova');
    fs.writeFileSync(sourceFilePath, updated, 'utf8');
}

function main() {

    const iosSourcePath = path.resolve(process.cwd(), 'src', 'ios');
    const files = fs.readdirSync(iosSourcePath, {withFileTypes: true})
        .filter(v => v.isFile())
        .map(v => path.resolve(iosSourcePath, v.name));
    
    for (const sourceFile of files) {
        stripDuplicateImports(sourceFile);
    }
}

main();