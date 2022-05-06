const express = require('express')
const fileSystem = require('fs')
require('dotenv').config()

const fetch = (...args) => import('node-fetch').then(({default: fetch}) => fetch(...args));

const app = express()
const fetchModule = async (repository, modulePath) => {
    const result = await fetch(`https://api.github.com/repos/Voutastic/${repository || 'mountain-hub'}/contents/${modulePath}`, {
        method: 'GET',
        headers: {
            Authorization: `token ${process.env.TOKEN}`,
            Accept: 'application/vnd.github.v4.raw'
        }
    })

    result.text().then(text => {
        console.log(text)
    })
}

app.get('/exports/:moduleFolder/:moduleName', async function(req, res) {
    const result = await fetch(`https://api.github.com/repos/Voutastic/mountain-hub/contents/${req.params.moduleFolder}/${req.params.moduleName}`, {
        method: 'GET',
        headers: {
            Authorization: `token ${process.env.TOKEN}`,
            Accept: 'application/vnd.github.v4.raw'
        }
    })

    result.text().then(text => {
        res.send(`
    <body>
        <pre style="style="word-wrap: break-word; white-space: pre-wrap;">${text}</pre>
    </body>
    `)
    })
})

app.listen(3000)
console.log('Listening to port 3000')