local totalFiles = 0
local filesDownloaded = 0
local projectName = ""
local authorName = ""

local titleTemplate = "Installing %s..."
local progressTemplate = "%s / %s files downloaded"
local urlBase = ""

local function setTotalFiles(n)
	totalFiles = n
end

local function setAuthorName(n)
	authorName = n
end

local function setProjectName(n)
	projectName = n
end

local function setUrlBase(u)
	urlBase = u
end

local function clearUI(isError)
	term.setTextColor(colors.white)
	term.setBackgroundColor(colors.black)
	term.clear()
	term.setCursorPos(1, 1)
	if not isError then
		print(projectName .. " is installed!")
	end
end

local function updateUI()
	local w, h = term.getSize()

	term.setTextColor(colors.black)
	term.setBackgroundColor(colors.white)
	term.clear()

	local progressText = string.format(progressTemplate, filesDownloaded, totalFiles)
	local titleText = string.format(titleTemplate, projectName .. (authorName ~= nil and "by " .. authorName or ""))
	local titleTextLength = #titleText
	local progressTextLength = #progressText

	term.setCursorPos(w / 2 - titleTextLength / 2, h / 2 - 1)
	term.write(titleText)
	term.setCursorPos(w / 2 - progressTextLength / 2, h / 2)
	term.write(progressText)
end

local function getFile(filePath)
	if fs.exists(filePath) then
		clearUI(true)
		error(filePath .. " already exists")
	end

	local response = http.get(urlBase .. filePath)
	local fileContent = response.readAll()
	response.close()

	local file = fs.open(filePath, "w")
	file.write(fileContent)
	file.close()

	filesDownloaded = filesDownloaded + 1
	updateUI()
end

local function tryMakeDir(dir)
	if dir == "/" then
		return
	end

	if not fs.exists(dir) then
		fs.makeDir(dir)
	end
end

updateUI()