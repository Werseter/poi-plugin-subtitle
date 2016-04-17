{_, SERVER_HOSTNAME} = window
Promise = require 'bluebird'
path = require 'path'
async = Promise.coroutine
fs = Promise.promisifyAll require('fs-extra'), { multiArgs: true }
request = Promise.promisifyAll require('request'), { multiArgs: true }
dbg.extra('subtitlesAudioResponse')
voiceMap = {}
shipgraph = {}
subtitles = {}
timeoutHandle = 0
REMOTE_HOST = 'http://api.kcwiki.moe/subtitles/diff'
subtitlesFile = path.join APPDATA_PATH, 'poi-plugin-subtitle', 'subtitles.json'
subtitlesFileBackup = path.join __dirname, 'subtitles.json'
voiceKey = [604825,607300,613847,615318,624009,631856,635451,637218,640529,643036,652687,658008,662481,669598,675545,685034,687703,696444,702593,703894,711191,714166,720579,728970,738675,740918,743009,747240,750347,759846,764051,770064,773457,779858,786843,790526,799973,803260,808441,816028,825381,827516,832463,837868,843091,852548,858315,867580,875771,879698,882759,885564,888837,896168]
convertFilename = (shipId, voiceId) ->
	return (shipId + 7) * 17 * (voiceKey[voiceId] - voiceKey[voiceId - 1]) % 99173 + 100000
for shipNo in [1..500]
	voiceMap[shipNo] = {}
	voiceMap[shipNo][convertFilename(shipNo,i)] = i for i in [1..voiceKey.length]

__ = i18n["poi-plugin-subtitle"].__.bind(i18n["poi-plugin-subtitle"])

getSubtitles = async () ->
	err = yield fs.ensureFileAsync subtitlesFile
	data = yield fs.readFileAsync subtitlesFile
	data = "{}" if not data or data.length is 0
	subtitles = JSON.parse data
	dataBackup = yield fs.readFileAsync subtitlesFileBackup
	subtitlesBackup = JSON.parse dataBackup
	if not subtitles?['version'] or +subtitles?['version'] < +subtitlesBackup?['version']
		data = dataBackup
		subtitles = subtitlesBackup
		err = yield fs.writeFileAsync subtitlesFile, data
		console.error err if err
	# Update subtitle data from remote server
	try
		[response, repData] = yield request.getAsync "#{REMOTE_HOST}/#{subtitles.version}"
		throw "获取字幕数据失败" unless repData
		rep = JSON.parse repData
		throw "字幕数据异常：#{rep.error}" if rep.error
		return unless rep.version
		for shipIdOrSth,value of rep
			if typeof value isnt "object"
				subtitles[shipIdOrSth] = value
			else
				subtitles[shipIdOrSth] = {} unless subtitles[shipIdOrSth]
				subtitles[shipIdOrSth][voiceId] = text for voiceId, text of value
		err = yield fs.writeFileAsync subtitlesFile, JSON.stringify(subtitles)
		throw err if err
	catch e
		if e instanceof Error
			console.error "#{e.name}: #{e.message}"
		else
			console.error e
		err = yield fs.writeFileAsync subtitlesFile, data
		console.error err if err
		subtitles = JSON.parse data
		# window.warn "语音字幕自动更新失败，请联系有关开发人员，并手动更新插件以更新字幕数据",
		#   stickyFor: 5000
		return
	window.success "语音字幕数据更新成功(#{subtitles.version})",
		stickyFor: 3000

initialize = (e) ->
	return if !localStorage.start2Body?
	body = JSON.parse localStorage.start2Body
	{_ships, _decks, _teitokuLv} = window
	shipgraph[ship.api_filename] = ship.api_id for ship in body.api_mst_shipgraph
	getSubtitles()

show = (text, prior, stickyFor) ->
	window.log "#{text}",
		priority : prior,
		stickyFor: stickyFor

handleGameResponse = (e) ->
	clearTimeout(timeoutHandle)

handleGetResponseDetails = (e) ->
	prior = 5
	match = /kcs\/sound\/kc(.*?)\/(.*?).mp3/.exec(e.newURL)
	return if not match? or match.length < 3
	console.log e.newURL if dbg.extra('subtitlesAudioResponse').isEnabled()
	[..., shipCode, fileName] = match
	apiId = shipgraph[shipCode]
	return if not apiId
	voiceId = voiceMap[apiId][fileName]
	return if not voiceId
	console.log "#{apiId} #{voiceId}" if dbg.extra('subtitlesAudioResponse').isEnabled()
	subtitle = subtitles[apiId]?[voiceId]
	console.log "i18n: #{__(apiId+'.'+voiceId)}" if dbg.extra('subtitlesAudioResponse').isEnabled()
	prior = 0 if 8 < voiceId < 11

	# Current not supprot for en-US and ja-JP, set default to zh-TW
	if i18n["poi-plugin-subtitle"].locale == 'en-US' or i18n["poi-plugin-subtitle"].locale == 'ja-JP'
		i18n["poi-plugin-subtitle"].locale = 'zh-TW'

	if voiceId < 30
		if subtitle
			show "#{$ships[apiId].api_name}：#{__(apiId+'.'+voiceId)}", prior, 5000
		else
			show "本【#{$ships[apiId].api_name}】的台词字幕缺失的说，来舰娘百科（http://zh.kcwiki.moe/）帮助我们补全台词吧！", prior, 5000          
	else
		now = new Date()
		sharpTime = new Date()
		sharpTime.setHours now.getHours()+1
		sharpTime.setMinutes 0
		sharpTime.setSeconds 0
		sharpTime.setMilliseconds 0
		diff = sharpTime - now
		diff = 0 if diff < 0
		timeoutHandle = setTimeout( ->
			if subtitle
				show "#{$ships[apiId].api_name}：#{subtitle}", prior, 5000
			else
				show "本【#{$ships[apiId].api_name}】的台词字幕缺失的说，来舰娘百科（http://zh.kcwiki.moe/）帮助我们补全台词吧！", prior, 5000
		,diff)

module.exports =
	show: false
	pluginDidLoad: (e) ->
		initialize()
		$('kan-game webview').addEventListener 'did-get-response-details', handleGetResponseDetails
		window.addEventListener 'game.response', handleGameResponse
	pluginWillUnload: (e) ->
		$('kan-game webview').removeEventListener 'did-get-response-details', handleGetResponseDetails
		window.removeEventListener 'game.response', handleGameResponse
