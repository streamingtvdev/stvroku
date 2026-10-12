' ********************************************************************
' * StreamingTV: Universal XC Media Player & Live Streaming Client
' * Main Application Entry Point & Event Loop
' ********************************************************************

sub Main(args as Dynamic)
    ' Initialize the SceneGraph screen
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.SetMessagePort(m.port)

    ' Create Root Scene
    m.scene = screen.CreateScene("MainScene")
    screen.Show()

    ' Pass initial launch arguments / deep links if present
    if args <> invalid and type(args) = "roAssociativeArray"
        if args.DoesExist("contentId")
            m.scene.deepLinkData = args
        end if
    end if

    ' Initialize roInput message receiver for deep linking during runtime
    input = CreateObject("roInput")
    input.SetMessagePort(m.port)

    ' Event Loop
    while(true)
        msg = wait(0, m.port)
        msgType = type(msg)

        if msgType = "roSGScreenEvent"
            if msg.isScreenClosed()
                exit while
            end if
        else if msgType = "roInputEvent"
            if msg.isInput()
                inputData = msg.GetInfo()
                if inputData <> invalid and inputData.DoesExist("contentId")
                    m.scene.deepLinkData = inputData
                end if
            end if
        end if
    end while
end sub
