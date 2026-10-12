' ********************************************************************
' * StreamingTV: LiveScreen Controller
' * 3-Pane: Category Rail -> Channel Column -> Preview/Synopsis
' * Network I/O runs in ApiTask (never on the render thread).
' ********************************************************************

sub init()
    m.categoryList = m.top.findNode("categoryList")
    m.channelList = m.top.findNode("channelList")
    m.chanLoadingLabel = m.top.findNode("chanLoadingLabel")
    m.chanHeaderLabel = m.top.findNode("chanHeaderLabel")
    m.catHeaderLabel = m.top.findNode("catHeaderLabel")
    m.nowBadge = m.top.findNode("nowBadge")
    
    m.previewVideo = m.top.findNode("previewVideo")
    m.previewPoster = m.top.findNode("previewPoster")
    m.previewLiveBadge = m.top.findNode("previewLiveBadge")
    m.activeChannelLogo = m.top.findNode("activeChannelLogo")
    m.activeChannelName = m.top.findNode("activeChannelName")
    
    m.nowTitleLabel = m.top.findNode("nowTitleLabel")
    m.nowTimeLabel = m.top.findNode("nowTimeLabel")
    m.nowDescLabel = m.top.findNode("nowDescLabel")
    m.nextTitleLabel = m.top.findNode("nextTitleLabel")
    
    m.previewDebounceTimer = m.top.findNode("previewDebounceTimer")
    m.epgRefreshTimer = m.top.findNode("epgRefreshTimer")
    
    m.categories = []
    m.channels = []
    m.currentCategoryIndex = 0
    m.currentChannelIndex = 0
    m.focusedPane = 1
    m.pendingCatId = "all"
    m.pendingCatName = ""
    
    isLowRam = IsLowMemoryDevice()
    prefPreview = Storage_GetPref("enable_live_preview", "")
    if prefPreview = "true"
        m.allowLivePreview = true
    else if prefPreview = "false"
        m.allowLivePreview = false
    else
        m.allowLivePreview = not isLowRam
    end if
    
    m.serverUrl = Storage_GetAuth("server_url", "")
    m.username = Storage_GetAuth("username", "")
    m.password = Storage_GetAuth("password", "")
    m.token = Storage_GetAuth("device_token", "")
    m.loginMode = Storage_GetAuth("login_mode", "xc")
    
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.observeField("response", "OnApiResponse")
    m.epgTask = CreateObject("roSGNode", "ApiTask")
    m.epgTask.observeField("response", "OnEpgResponse")
    
    m.categoryList.observeField("itemSelected", "OnCategorySelected")
    m.channelList.observeField("itemFocused", "OnChannelFocused")
    m.channelList.observeField("itemSelected", "OnChannelSelected")
    
    m.previewDebounceTimer.observeField("fire", "OnPreviewDebounceFired")
    m.epgRefreshTimer.observeField("fire", "OnEpgRefreshFired")
    
    LoadCategories()
    OnThemeChanged()
end sub

sub OnThemeChanged()
    theme = m.top.theme
    if theme = invalid then return
    
    if m.catHeaderLabel <> invalid then m.catHeaderLabel.color = theme.accentPrimary
    if m.chanHeaderLabel <> invalid then m.chanHeaderLabel.color = theme.accentPrimary
    if m.previewLiveBadge <> invalid then m.previewLiveBadge.color = theme.accentPrimary
    if m.nowBadge <> invalid then m.nowBadge.color = theme.accentPrimary
    if m.nextTitleLabel <> invalid then m.nextTitleLabel.color = theme.accentFocused
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

' ====================================================================
' Data Loading
' ====================================================================

sub LoadCategories()
    m.chanLoadingLabel.visible = true
    m.chanLoadingLabel.text = "Loading categories..."
    
    args = XcArgs()
    FireApi("get_live_categories", args, "categories")
end sub

sub OnApiResponse()
    resp = m.apiTask.response
    if resp = invalid then return
    ctx = resp.context
    
    if ctx = "categories"
        catList = []
        catList.Push({ category_id: "all", category_name: "★ All Channels" })
        
        if resp.success and type(resp.data) = "roArray"
            for each cat in resp.data
                if cat <> invalid and cat.DoesExist("category_name")
                    catList.Push(cat)
                end if
            end for
        end if
        
        m.categories = catList
        content = CreateObject("roSGNode", "ContentNode")
        for each cat in m.categories
            item = content.CreateChild("ContentNode")
            item.title = cat.category_name
        end for
        m.categoryList.content = content
        
        if m.categories.Count() > 0
            LoadChannelsForCategory(m.categories[0].category_id, m.categories[0].category_name)
        end if
        
    else if ctx = "channels"
        streamList = []
        if resp.success and type(resp.data) = "roArray"
            for each s in resp.data
                if s <> invalid and s.DoesExist("name")
                    streamList.Push(s)
                end if
            end for
        end if
        
        m.channels = streamList
        content = CreateObject("roSGNode", "ContentNode")
        for each ch in m.channels
            item = content.CreateChild("ContentNode")
            item.title = ch.name
        end for
        m.channelList.content = content
        
        if m.channels.Count() > 0
            m.chanLoadingLabel.visible = false
            m.channelList.jumpToItem = 0
            m.channelList.setFocus(true)
            m.focusedPane = 1
            OnChannelFocused()
        else
            m.chanLoadingLabel.visible = true
            if resp.success
                m.chanLoadingLabel.text = "No channels in this category."
            else
                m.chanLoadingLabel.text = "Could not load channels. Press OK to retry."
            end if
            m.activeChannelName.text = "No channels available"
        end if
    end if
end sub

sub LoadChannelsForCategory(catId as String, catName as String)
    m.pendingCatId = catId
    m.pendingCatName = catName
    m.chanLoadingLabel.visible = true
    m.chanLoadingLabel.text = "Loading channels..."
    m.channelList.content = invalid
    m.chanHeaderLabel.text = UCase(catName)
    
    args = XcArgs()
    args.categoryId = catId
    FireApi("get_live_streams", args, "channels")
end sub

' ====================================================================
' Navigation & Focus Handling
' ====================================================================

sub OnCategorySelected()
    idx = m.categoryList.itemSelected
    if idx >= 0 and idx < m.categories.Count()
        m.currentCategoryIndex = idx
        cat = m.categories[idx]
        LoadChannelsForCategory(cat.category_id, cat.category_name)
    end if
end sub

sub OnChannelFocused()
    idx = m.channelList.itemFocused
    if idx < 0 or idx >= m.channels.Count() then return
    
    m.currentChannelIndex = idx
    ch = m.channels[idx]
    
    m.activeChannelName.text = ch.name
    if ch.DoesExist("stream_icon") and ch.stream_icon <> ""
        m.activeChannelLogo.uri = ch.stream_icon
        m.previewPoster.uri = ch.stream_icon
    else
        m.activeChannelLogo.uri = "pkg:/images/channel_placeholder.png"
        m.previewPoster.uri = "pkg:/images/channel_placeholder.png"
    end if
    
    m.nowTitleLabel.text = "Fetching Guide..."
    m.nowTimeLabel.text = ""
    m.nowDescLabel.text = ""
    m.nextTitleLabel.text = ""
    
    m.previewDebounceTimer.control = "stop"
    m.epgRefreshTimer.control = "stop"
    m.previewDebounceTimer.control = "start"
    m.epgRefreshTimer.control = "start"
end sub

sub OnEpgRefreshFired()
    if m.currentChannelIndex < 0 or m.currentChannelIndex >= m.channels.Count() then return
    ch = m.channels[m.currentChannelIndex]
    sid = ""
    if ch.DoesExist("stream_id") then sid = AnyToStr(ch.stream_id)
    if sid = "" then return
    
    args = XcArgs()
    args.streamId = sid
    m.epgTask.context = "epg"
    m.epgTask.action = "get_short_epg"
    m.epgTask.args = args
    m.epgTask.control = "RUN"
end sub

sub OnEpgResponse()
    resp = m.epgTask.response
    if resp = invalid then return
    if m.currentChannelIndex < 0 or m.currentChannelIndex >= m.channels.Count() then return
    ch = m.channels[m.currentChannelIndex]
    
    epgData = resp.data
    if resp.success and type(epgData) = "roAssociativeArray" and epgData.DoesExist("epg_listings")
        listings = epgData.epg_listings
        if type(listings) = "roArray" and listings.Count() > 0
            cur = listings[0]
            if cur.DoesExist("title") then m.nowTitleLabel.text = EpgText(cur.title)
            
            timeStr = ""
            if cur.DoesExist("start") and cur.DoesExist("end")
                timeStr = FormatUnixTime(cur.start) + " - " + FormatUnixTime(cur.end)
            end if
            m.nowTimeLabel.text = timeStr
            
            if cur.DoesExist("description") then m.nowDescLabel.text = EpgText(cur.description)
            
            if listings.Count() > 1
                nxt = listings[1]
                nxtTitle = ""
                if nxt.DoesExist("title") then nxtTitle = EpgText(nxt.title)
                nxtTime = ""
                if nxt.DoesExist("start") then nxtTime = " (" + FormatUnixTime(nxt.start) + ")"
                m.nextTitleLabel.text = "NEXT: " + nxtTitle + nxtTime
            end if
            return
        end if
    end if
    
    m.nowTitleLabel.text = ch.name
    m.nowDescLabel.text = "Live Broadcast"
end sub

sub OnPreviewDebounceFired()
    if not m.allowLivePreview then return
    if m.currentChannelIndex < 0 or m.currentChannelIndex >= m.channels.Count() then return
    ch = m.channels[m.currentChannelIndex]
    
    sid = ""
    if ch.DoesExist("stream_id") then sid = AnyToStr(ch.stream_id)
    if sid = "" then return
    
    cleanBase = CleanServerUrl(m.serverUrl)
    streamUrl = cleanBase + "/live/" + m.username.Trim() + "/" + m.password.Trim() + "/" + sid + ".m3u8"
    
    content = CreateObject("roSGNode", "ContentNode")
    content.url = streamUrl
    content.streamFormat = "hls"
    
    m.previewVideo.content = content
    m.previewVideo.control = "play"
    m.previewLiveBadge.visible = true
    m.previewPoster.visible = false
end sub

sub StopPreviewVideo()
    m.previewVideo.control = "stop"
    m.previewLiveBadge.visible = false
    m.previewPoster.visible = true
end sub

sub OnChannelSelected()
    idx = m.channelList.itemSelected
    if idx < 0 or idx >= m.channels.Count()
        ' OK on the empty/error label retries
        if m.channels.Count() = 0 and m.pendingCatId <> ""
            LoadChannelsForCategory(m.pendingCatId, m.pendingCatName)
        end if
        return
    end if
    
    ch = m.channels[idx]
    sid = ""
    if ch.DoesExist("stream_id") then sid = AnyToStr(ch.stream_id)
    if sid = "" then return
    
    StopPreviewVideo()
    
    cleanBase = CleanServerUrl(m.serverUrl)
    streamUrl = cleanBase + "/live/" + m.username.Trim() + "/" + m.password.Trim() + "/" + sid + ".m3u8"
    
    payload = {
        channel: ch,
        streamUrl: streamUrl,
        channelIndex: idx,
        allChannels: m.channels,
        categoryName: m.chanHeaderLabel.text
    }
    
    m.top.playFullscreen = payload
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    
    if key = "left"
        if m.focusedPane = 1
            m.focusedPane = 0
            m.categoryList.setFocus(true)
            return true
        end if
    else if key = "right"
        if m.focusedPane = 0
            m.focusedPane = 1
            m.channelList.setFocus(true)
            return true
        end if
    end if
    
    return false
end function
