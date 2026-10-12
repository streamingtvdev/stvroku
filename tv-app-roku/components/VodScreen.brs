' ********************************************************************
' * StreamingTV: VodScreen Controller
' * Movies and Series browsing, poster grid, details modal, episode picker.
' * Network I/O runs in ApiTask (never on the render thread).
' ********************************************************************

sub init()
    m.categoryList = m.top.findNode("categoryList")
    m.mediaGrid = m.top.findNode("mediaGrid")
    m.gridLoadingLabel = m.top.findNode("gridLoadingLabel")
    m.catHeaderLabel = m.top.findNode("catHeaderLabel")
    m.gridHeaderLabel = m.top.findNode("gridHeaderLabel")
    
    m.detailsModal = m.top.findNode("detailsModal")
    m.modalPoster = m.top.findNode("modalPoster")
    m.modalTitle = m.top.findNode("modalTitle")
    m.modalMeta = m.top.findNode("modalMeta")
    m.modalPlot = m.top.findNode("modalPlot")
    m.btnModalPlay = m.top.findNode("btnModalPlay")
    m.btnModalBack = m.top.findNode("btnModalBack")
    
    m.categories = []
    m.mediaItems = []
    m.currentCatIndex = 0
    m.selectedItem = invalid
    m.focusedPane = 1
    m.modalButtonIndex = 0
    m.episodeMode = false
    m.selectedSeries = invalid
    m.pendingCatId = "all"
    m.pendingCatName = ""
    
    m.serverUrl = Storage_GetAuth("server_url", "")
    m.username = Storage_GetAuth("username", "")
    m.password = Storage_GetAuth("password", "")
    
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.observeField("response", "OnApiResponse")
    
    m.categoryList.observeField("itemSelected", "OnCategorySelected")
    m.mediaGrid.observeField("itemSelected", "OnMediaItemSelected")
    
    LoadCategories()
    OnThemeChanged()
end sub

sub OnThemeChanged()
    theme = m.top.theme
    if theme <> invalid
        if m.catHeaderLabel <> invalid then m.catHeaderLabel.color = theme.accentPrimary
        if m.gridHeaderLabel <> invalid then m.gridHeaderLabel.color = theme.accentPrimary
        if m.modalMeta <> invalid then m.modalMeta.color = theme.accentPrimary
        UpdateModalButtonStyles()
    end if
end sub

sub FireApi(action as String, args as Object, context as String)
    m.apiTask.context = context
    m.apiTask.action = action
    m.apiTask.args = args
    m.apiTask.control = "RUN"
end sub

sub XcArgs() as Object
    return {
        serverUrl: m.serverUrl,
        username: m.username,
        password: m.password
    }
end sub

sub LoadCategories()
    isSeries = (m.top.vodType = "series")
    if isSeries
        m.catHeaderLabel.text = "SERIES GENRES"
        m.gridHeaderLabel.text = "ALL SERIES"
    else
        m.catHeaderLabel.text = "MOVIE GENRES"
        m.gridHeaderLabel.text = "ALL MOVIES"
    end if
    
    m.gridLoadingLabel.visible = true
    m.gridLoadingLabel.text = "Loading categories..."
    
    action = "get_vod_categories"
    if isSeries then action = "get_series_categories"
    FireApi(action, XcArgs(), "categories")
end sub

sub LoadMediaForCategory(catId as String, catName as String)
    m.episodeMode = false
    m.selectedSeries = invalid
    m.pendingCatId = catId
    m.pendingCatName = catName
    m.gridLoadingLabel.visible = true
    m.gridLoadingLabel.text = "Loading titles..."
    m.mediaGrid.content = invalid
    m.gridHeaderLabel.text = UCase(catName)
    
    isSeries = (m.top.vodType = "series")
    action = "get_vod_streams"
    if isSeries then action = "get_series"
    
    args = XcArgs()
    args.categoryId = catId
    FireApi(action, args, "media")
end sub

sub OnApiResponse()
    resp = m.apiTask.response
    if resp = invalid then return
    ctx = resp.context
    
    if ctx = "categories"
        catList = []
        catList.Push({ category_id: "all", category_name: "★ All Titles" })
        if resp.success and type(resp.data) = "roArray"
            for each cat in resp.data
                if cat <> invalid and cat.DoesExist("category_name")
                    catList.Push(cat)
                end if
            end for
        end if
        
        m.categories = catList
        content = CreateObject("roSGNode", "ContentNode")
        for each c in m.categories
            item = content.CreateChild("ContentNode")
            item.title = c.category_name
        end for
        m.categoryList.content = content
        
        if m.categories.Count() > 0
            LoadMediaForCategory(m.categories[0].category_id, m.categories[0].category_name)
        end if
        
    else if ctx = "media"
        itemList = []
        if resp.success and type(resp.data) = "roArray"
            for each itm in resp.data
                if itm <> invalid and itm.DoesExist("name")
                    itemList.Push(itm)
                end if
            end for
        end if
        ShowMediaItems(itemList, resp.success, "")
        
    else if ctx = "episodes"
        episodes = ParseSeriesEpisodes(resp)
        if episodes.Count() > 0
            m.selectedSeries = m.selectedItem
            m.episodeMode = true
            seriesName = ""
            if m.selectedSeries <> invalid and m.selectedSeries.DoesExist("name")
                seriesName = m.selectedSeries.name
            end if
            ShowMediaItems(episodes, true, "EPISODES • " + UCase(TruncateText(seriesName, 40)))
        else
            m.gridLoadingLabel.visible = true
            if resp.success
                m.gridLoadingLabel.text = "No episodes found."
            else
                m.gridLoadingLabel.text = "Could not load episodes. Press OK to retry."
            end if
        end if
    end if
end sub

sub ShowMediaItems(itemList as Object, ok as Boolean, headerText as String)
    m.mediaItems = itemList
    if headerText <> "" then m.gridHeaderLabel.text = headerText
    
    content = CreateObject("roSGNode", "ContentNode")
    for each itm in m.mediaItems
        item = content.CreateChild("ContentNode")
        item.title = itm.name
        posterUrl = "pkg:/images/channel_placeholder.png"
        if itm.DoesExist("stream_icon") and itm.stream_icon <> ""
            posterUrl = itm.stream_icon
        else if itm.DoesExist("cover") and itm.cover <> ""
            posterUrl = itm.cover
        end if
        item.hdPosterUrl = posterUrl
    end for
    m.mediaGrid.content = content
    
    if m.mediaItems.Count() > 0
        m.gridLoadingLabel.visible = false
        m.mediaGrid.jumpToItem = 0
        m.mediaGrid.setFocus(true)
        m.focusedPane = 1
    else
        m.gridLoadingLabel.visible = true
        if ok
            m.gridLoadingLabel.text = "No titles found in this category."
        else
            m.gridLoadingLabel.text = "Could not load titles. Press OK to retry."
        end if
    end if
end sub

' Flatten XC get_series_info episodes into a playable list.
function ParseSeriesEpisodes(resp as Object) as Object
    episodes = []
    data = resp.data
    if not resp.success or data = invalid or type(data) <> "roAssociativeArray" then return episodes
    if not data.DoesExist("episodes") then return episodes
    epMap = data.episodes
    if type(epMap) <> "roAssociativeArray" then return episodes
    
    coverUrl = ""
    if m.selectedItem <> invalid
        if m.selectedItem.DoesExist("stream_icon") and m.selectedItem.stream_icon <> ""
            coverUrl = m.selectedItem.stream_icon
        else if m.selectedItem.DoesExist("cover") and m.selectedItem.cover <> ""
            coverUrl = m.selectedItem.cover
        end if
    end if
    
    seriesId = ""
    if m.selectedItem <> invalid and m.selectedItem.DoesExist("series_id")
        seriesId = AnyToStr(m.selectedItem.series_id)
    end if
    
    seasonNums = []
    for each k in epMap
        seasonNums.Push(Val(k))
    end for
    for i = 0 to seasonNums.Count() - 2
        for j = i + 1 to seasonNums.Count() - 1
            if seasonNums[j] < seasonNums[i]
                tmp = seasonNums[i]
                seasonNums[i] = seasonNums[j]
                seasonNums[j] = tmp
            end if
        end for
    end for
    
    for each sNum in seasonNums
        seasonKey = Str(sNum).Trim()
        eps = invalid
        if epMap.DoesExist(seasonKey) then eps = epMap[seasonKey]
        if type(eps) = "roArray"
            for each ep in eps
                epId = ""
                if ep.DoesExist("id") then epId = AnyToStr(ep.id)
                if epId <> ""
                    epTitle = "Episode"
                    if ep.DoesExist("title") and ep.title <> "" then epTitle = ep.title
                    epNum = 0
                    if ep.DoesExist("episode_num") then epNum = ep.episode_num
                    ext = "mp4"
                    if ep.DoesExist("container_extension") and ep.container_extension <> ""
                        ext = ep.container_extension
                    end if
                    plotStr = ""
                    if ep.DoesExist("info") and type(ep.info) = "roAssociativeArray"
                        if ep.info.DoesExist("plot") then plotStr = ep.info.plot
                    end if
                    episodes.Push({
                        name: "S" + seasonKey + "E" + Str(epNum).Trim() + " • " + epTitle,
                        stream_id: epId,
                        container_extension: ext,
                        stream_icon: coverUrl,
                        plot: plotStr,
                        series_id: seriesId
                    })
                end if
            end for
        end if
    end for
    
    return episodes
end function

sub OnCategorySelected()
    idx = m.categoryList.itemSelected
    if idx >= 0 and idx < m.categories.Count()
        m.currentCatIndex = idx
        cat = m.categories[idx]
        LoadMediaForCategory(cat.category_id, cat.category_name)
    end if
end sub

sub OnMediaItemSelected()
    idx = m.mediaGrid.itemSelected
    if idx < 0 or idx >= m.mediaItems.Count()
        if m.mediaItems.Count() = 0 and m.pendingCatId <> ""
            LoadMediaForCategory(m.pendingCatId, m.pendingCatName)
        end if
        return
    end if
    
    m.selectedItem = m.mediaItems[idx]
    m.modalTitle.text = m.selectedItem.name
    
    posterUrl = "pkg:/images/channel_placeholder.png"
    if m.selectedItem.DoesExist("stream_icon") and m.selectedItem.stream_icon <> ""
        posterUrl = m.selectedItem.stream_icon
    else if m.selectedItem.DoesExist("cover") and m.selectedItem.cover <> ""
        posterUrl = m.selectedItem.cover
    end if
    m.modalPoster.uri = posterUrl
    
    ratingStr = ""
    if m.selectedItem.DoesExist("rating") and m.selectedItem.rating <> ""
        ratingStr = AnyToStr(m.selectedItem.rating)
    end if
    if ratingStr <> ""
        m.modalMeta.text = "Rating: ★ " + ratingStr
    else
        m.modalMeta.text = ""
    end if
    
    plotStr = "No plot synopsis available."
    if m.selectedItem.DoesExist("plot") and m.selectedItem.plot <> ""
        plotStr = m.selectedItem.plot
    end if
    m.modalPlot.text = plotStr
    
    ' Series root: PLAY NOW opens the episode list instead of streaming.
    m.detailsModal.visible = true
    m.focusedPane = 2
    m.modalButtonIndex = 0
    UpdateModalButtonStyles()
end sub

sub UpdateModalButtonStyles()
    theme = m.top.theme
    if theme = invalid then theme = GetDefaultTheme()
    
    if m.modalButtonIndex = 0
        m.btnModalPlay.color = theme.accentFocused
        m.btnModalBack.color = theme.cardColor
    else
        m.btnModalPlay.color = theme.accentPrimary
        m.btnModalBack.color = "0x323846FF"
    end if
end sub

sub PlaySelectedItem()
    if m.selectedItem = invalid then return
    
    isSeries = (m.top.vodType = "series")
    
    if isSeries and not m.episodeMode
        ShowSeriesEpisodes()
        return
    end if
    
    sid = ""
    ext = "mp4"
    if m.selectedItem.DoesExist("stream_id")
        sid = AnyToStr(m.selectedItem.stream_id)
    else if m.selectedItem.DoesExist("series_id")
        sid = AnyToStr(m.selectedItem.series_id)
    end if
    if m.selectedItem.DoesExist("container_extension") and m.selectedItem.container_extension <> ""
        ext = m.selectedItem.container_extension
    end if
    
    cleanBase = CleanServerUrl(m.serverUrl)
    pathType = "movie"
    if isSeries then pathType = "series"
    
    streamUrl = cleanBase + "/" + pathType + "/" + m.username.Trim() + "/" + m.password.Trim() + "/" + sid + "." + ext
    
    m.detailsModal.visible = false
    m.focusedPane = 1
    
    payload = {
        channel: m.selectedItem,
        streamUrl: streamUrl,
        channelIndex: 0,
        allChannels: [m.selectedItem],
        categoryName: m.gridHeaderLabel.text
    }
    
    m.top.playMedia = payload
end sub

sub ShowSeriesEpisodes()
    if m.selectedItem = invalid then return
    
    seriesId = ""
    if m.selectedItem.DoesExist("series_id") then seriesId = AnyToStr(m.selectedItem.series_id)
    if seriesId = "" then return
    
    m.detailsModal.visible = false
    m.focusedPane = 1
    m.gridLoadingLabel.visible = true
    m.gridLoadingLabel.text = "Loading episodes..."
    m.mediaGrid.content = invalid
    
    args = XcArgs()
    args.seriesId = seriesId
    FireApi("get_series_info", args, "episodes")
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    
    if m.focusedPane = 2
        if key = "back"
            m.detailsModal.visible = false
            m.focusedPane = 1
            m.mediaGrid.setFocus(true)
            return true
        else if key = "left" or key = "right"
            m.modalButtonIndex = 1 - m.modalButtonIndex
            UpdateModalButtonStyles()
            return true
        else if key = "OK"
            if m.modalButtonIndex = 0
                PlaySelectedItem()
            else
                m.detailsModal.visible = false
                m.focusedPane = 1
                m.mediaGrid.setFocus(true)
            end if
            return true
        end if
        return true
    end if
    
    if key = "back" and m.episodeMode
        m.episodeMode = false
        m.selectedSeries = invalid
        if m.categories.Count() > 0 and m.currentCatIndex < m.categories.Count()
            cat = m.categories[m.currentCatIndex]
            LoadMediaForCategory(cat.category_id, cat.category_name)
        end if
        return true
    end if
    
    if key = "left"
        if m.focusedPane = 1
            m.focusedPane = 0
            m.categoryList.setFocus(true)
            return true
        end if
    else if key = "right"
        if m.focusedPane = 0
            m.focusedPane = 1
            m.mediaGrid.setFocus(true)
            return true
        end if
    end if
    
    return false
end function
