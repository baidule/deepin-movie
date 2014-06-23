import QtQuick 2.1
import QtMultimedia 5.0

MouseArea {
    id: mouse_area
    focus: true
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    anchors.fill: window

    property var window
    property int resizeEdge
    property int triggerThreshold: 10  // threshold for resizing the window
    property int cornerTriggerThreshold: 20

    property int dragStartX
    property int dragStartY
    property int windowLastX
    property int windowLastY

    property bool shouldPlayOrPause: true

    property int movieDuration: movieInfo.movie_duration

    ResizeEdge { id: resize_edge }
    MenuResponder { id: menu_responder }
    KeysResponder { id: keys_responder }

    Connections {
        target: movieInfo

        // Notice:
        // QWindow.setHeight probably will not set the actual height of the
        // window to the given value(automatically adjusted by the WM or something),
        // though QWindow.height is set to the given value actually,
        // so QWindow.height is not reliable here to get the actual height of the window,

        // property int width: 0
        // property int height: 0
        // onMovieWidthChanged: { width = movieInfo.movie_width; setSizeForRootWindow() } 
        // onMovieHeightChanged: { height = movieInfo.movie_height; setSizeForRootWindow() }

        // function setSizeForRootWindow() {
        //     if (config.playerAdjustType == "ADJUST_TYPE_VIDEO_WINDOW" || config.playerAdjustType == "ADJUST_TYPE_LAST_TIME") {
        //         // nothing here
        //     } else if (config.playerAdjustType == "ADJUST_TYPE_WINDOW_VIDEO") {
        //         if (width != 0 && height != 0) {
        //             if (primaryRect.width / primaryRect.height > movieInfo.movie_width / movieInfo.movie_height) {
        //                 if (movieInfo.movie_height > primaryRect.height) {
        //                     windowView.setHeight(primaryRect.height)
        //                     windowView.setWidth(primaryRect.height * root.widthHeightScale)
        //                 } else {
        //                     windowView.setHeight(movieInfo.movie_height)
        //                     windowView.setWidth(movieInfo.movie_height * root.widthHeightScale)
        //                 }
        //             } else {
        //                 if (movieInfo.movie_width > primaryRect.width) {
        //                     windowView.setWidth(primaryRect.width)
        //                     windowView.setHeight(primaryRect.width / root.widthHeightScale)
        //                 } else {
        //                     windowView.setWidth(movieInfo.movie_width)
        //                     windowView.setHeight(movieInfo.movie_width / root.widthHeightScale)
        //                 }
        //             }

        //             width = 0
        //             height = 0
        //         }
        //     } else if (config.playerAdjustType == "ADJUST_TYPE_FULLSCREEN") {
        //         fullscreen()
        //     }
        // }

        onMovieWidthChanged: {
            if (titlebar.state == "minimal") {
                backupWidth = movieInfo.movie_width
                _setSizeForRootWindowWithWidth(windowView.width)
                return
            }
            if (movieInfo.movie_width == 856) {// first start
                if (config.applyLastClosedSize) {
                    _setSizeForRootWindowWithWidth(lastWindowWidth)
                } else {
                    windowView.setWidth(windowView.defaultWidth)
                    windowView.setHeight(windowView.defaultHeight)    
                }
            } else {
                var destWidth = hasResized ? windowView.width : movieInfo.movie_width 
                _setSizeForRootWindowWithWidth(destWidth)    
            }
            windowView.centerRequestCount-- > 0 && windowView.moveToCenter()
        }

        onMovieSourceChanged: {
            var last_watched_pos = database.fetch_video_position(player.source)
            if (config.playerAutoPlayFromLast 
                && Math.abs(last_watched_pos - movieInfo.movie_duration) > program_constants.videoEndsThreshold) {
                seek_to_last_watched_timer.schedule(last_watched_pos)
            } else {
                play()
            }

            playlist.hide()
            titlebar.show()
            controlbar.show()
        }

        onFileInvalid: {
            notifybar.show(dsTr("Invalid file"))
            root.reset()
        }
    }

    Timer {
        id: seek_to_last_watched_timer
        interval: 500

        property int last_watched_pos

        function schedule(pos) {
            start()
            last_watched_pos = pos
        }

        onTriggered: {
            player.seek(last_watched_pos)
            play()
        }
    }

    Timer {
        id: show_playlist_timer
        interval: 3000

        onTriggered: {
            if (mouseX >= main_window.width - program_constants.playlistTriggerThreshold) {
                hideControls()
                playlist.state = "active"
                playlist.show()
            }
        }
    }

    Timer {
        id: hide_mouse_timer
        interval: 1000 * 10

        onTriggered: {
            if (player.playbackState == MediaPlayer.PlayingState) 
                mouse_area.cursorShape = Qt.BlankCursor
        }
    }

    property int clickCount: 0
    Timer {
        id: double_click_check_timer
        interval: 300

        onTriggered: {
            if (mouse_area.clickCount == 1) {
                mouse_area.doSingleClick()
            } else if (mouse_area.clickCount == 2) {
                mouse_area.doDoubleClick()
            }
            mouse_area.clickCount = 0
        }
    }

    function _setSizeForRootWindowWithWidth(destWidth) {
        var widthHeightScale = (movieInfo.movie_width - 2 * program_constants.windowGlowRadius) / (movieInfo.movie_height - 2 * program_constants.windowGlowRadius)
        var destHeight = (destWidth - program_constants.windowGlowRadius * 2) / widthHeightScale + program_constants.windowGlowRadius * 2
        if (destHeight > primaryRect.height) {
            windowView.setWidth((primaryRect.height - 2 * program_constants.windowGlowRadius) * widthHeightScale + 2 * program_constants.windowGlowRadius)
            windowView.setHeight(primaryRect.height)
        } else {
            windowView.setWidth(destWidth)
            windowView.setHeight(destHeight)
        }
    }

    function setWindowTitle(title) {
        titlebar.title = title
        windowView.setTitle(title)
    }

    // resize operation related
    function getEdge(mouse) {
        if (windowView.getState() == Qt.WindowFullScreen) return resize_edge.resizeNone
        // four corners
        if (0 < mouse.x && mouse.x < cornerTriggerThreshold) {
            if (0 < mouse.y && mouse.y < cornerTriggerThreshold)
                return resize_edge.resizeTopLeft
            if (window.height - cornerTriggerThreshold < mouse.y && mouse.y < window.height)
                return resize_edge.resizeBottomLeft
        } else if (window.width - cornerTriggerThreshold < mouse.x && mouse.x < window.width) {
            if (0 < mouse.y && mouse.y < cornerTriggerThreshold)
                return resize_edge.resizeTopRight
            if (window.height - cornerTriggerThreshold < mouse.y && mouse.y < window.height)
                return resize_edge.resizeBottomRight
        }
        // four sides
        if (0 < mouse.x && mouse.x < triggerThreshold) {
            return resize_edge.resizeLeft
        } else if (window.width - triggerThreshold < mouse.x && mouse.x < window.width) {
            return resize_edge.resizeRight
        } else if (0 < mouse.y && mouse.y < triggerThreshold){
            return resize_edge.resizeTop
        } else if (window.height - triggerThreshold < mouse.y && mouse.y < window.height) {
            return resize_edge.resizeBottom
        } 

        return resize_edge.resizeNone
    }

    function changeCursor(resizeEdge) {
        if (resizeEdge == resize_edge.resizeLeft || resizeEdge == resize_edge.resizeRight) {
            cursorShape = Qt.SizeHorCursor
        } else if (resizeEdge == resize_edge.resizeTop || resizeEdge == resize_edge.resizeBottom) {
            cursorShape = Qt.SizeVerCursor
        } else if (resizeEdge == resize_edge.resizeTopLeft || resizeEdge == resize_edge.resizeBottomRight) {
            cursorShape = Qt.SizeFDiagCursor
        } else if (resizeEdge == resize_edge.resizeBottomLeft || resizeEdge == resize_edge.resizeTopRight){
            cursorShape = Qt.SizeBDiagCursor
        } else {
            cursorShape = Qt.ArrowCursor
        }
    }

    function doSingleClick() {
        if (playlist.expanded) {
            playlist.hide()
            return
        }

        if (config.othersLeftClick) {
            if (shouldPlayOrPause) {
                if (player.playbackState == MediaPlayer.PausedState) {
                    play()
                } else if (player.playbackState == MediaPlayer.PlayingState) {
                    pause()
                }
            } else {
                shouldPlayOrPause = true
            }
        }
    }

    function doDoubleClick(mouse) {
        if (player.playbackState != MediaPlayer.StoppedState) {
            if (config.othersDoubleClick) {
                toggleFullscreen()
            }            
        } else {
            openFile()
        }
    }

    function urlToPlaylistItem(serie, url) {
        url = url.indexOf("file://") != -1 ? url : "file://" + url
        var pathDict = url.split("/")
        var result = pathDict.slice(pathDict.length - 2, pathDict.length + 1)
        return serie ? [serie, [result[result.length - 1].toString(), url.toString()]]
                        : [[result[result.length - 1].toString(), url.toString()]]
    }

    function addPlayListItem(url) { 
        var serie = config.playerAutoPlaySeries ? JSON.parse(_utils.getSeriesByName(url)) : null
        if (serie && serie.name != "") {
            for (var i = 0; i < serie.items.length; i++) {
                playlist.addItem(urlToPlaylistItem(serie.name, serie.items[i]))
            }
        } else {
            playlist.addItem(urlToPlaylistItem("", url))
        }
    }

    function close() {
        windowView.close()
    }

    function normalize() {
        root.state = "normal"
        _utils.enable_zone()
        windowView.showNormal()
    }

    property bool fullscreenFromMaximum: false
    function fullscreen() {
        backupWidth = windowView.width
        fullscreenFromMaximum = (windowView.getState() == Qt.WindowMaximized)
        root.state = "no_glow"
        _utils.disable_zone()
        windowView.showFullScreen()
    }

    function quitFullscreen() { fullscreenFromMaximum ? maximize() : normalize() }

    function maximize() {
        backupWidth = windowView.width
        root.state = "no_glow"
        _utils.enable_zone()
        windowView.showMaximized()
    }

    function minimize() {
        root.state = "normal"
        _utils.enable_zone()
        windowView.doMinimized()
    }

    property int backupWidth: 0
    function toggleMiniMode() {
        if (titlebar.state == "minimal") {
            titlebar.state = "normal"
            windowView.staysOnTop = false
            _setSizeForRootWindowWithWidth(backupWidth)
        } else {
            if (windowView.getState() != Qt.WindowMaximized 
                && windowView.getState() != Qt.WindowFullScreen)
            {
                backupWidth = windowView.width
            }
            normalize()
            titlebar.state = "minimal"
            windowView.staysOnTop = true
            _setSizeForRootWindowWithWidth(program_constants.miniModeWidth)
        }
    }

    function setProportion(propWidth, propHeight) {
        var widthHeightScale = propWidth / propHeight
        if (root.height * widthHeightScale > primaryRect.width) {
            windowView.setHeight((primaryRect.width) / widthHeightScale)
            windowView.setWidth(primaryRect.width)
        }
        root.widthHeightScale = widthHeightScale
        windowView.setWidth(root.height * widthHeightScale)
    }

    function setScale(scale) {
        if (primaryRect.width / primaryRect.height > movieInfo.movie_width / movieInfo.movie_height) {
            if (movieInfo.movie_width * scale > primaryRect.width) {
                windowView.setWidth(primaryRect.width)
                windowView.setHeight(primaryRect.width / root.widthHeightScale)
            } else {
                windowView.setWidth(movieInfo.movie_width * scale)
                windowView.setHeight(movieInfo.movie_width * scale / root.widthHeightScale)
            }
        } else {
            if (movieInfo.movie_height * scale > primaryRect.height) {
                windowView.setHeight(primaryRect.height)
                windowView.setWidth(primaryRect.height * root.widthHeightScale)
            } else {
                windowView.setHeight(movieInfo.movie_height * scale)
                windowView.setWidth(movieInfo.movie_height * scale * root.widthHeightScale)
            }
        }
    }

    function toggleFullscreen() {
        windowView.getState() == Qt.WindowFullScreen ? quitFullscreen() : fullscreen()
    }

    function toggleMaximized() {
        windowView.getState() == Qt.WindowMaximized ? normalize() : maximize()
    }

    function toggleStaysOnTop() {
        windowView.staysOnTop = !windowView.staysOnTop
    }

    function flipHorizontal() { player.flipHorizontal(); controlbar.flipPreviewHorizontal() }
    function flipVertical() { player.flipVertical(); controlbar.flipPreviewVertical() }
    function rotateClockwise() { player.rotateClockwise(); controlbar.rotatePreviewClockwise() }
    function rotateAnticlockwise() { player.rotateAnticlockwise(); controlbar.rotatePreviewAntilockwise() }

    // player control operation related
    function play() { player.play() }
    function pause() { player.pause() }
    function stop() { player.stop() }

    function togglePlay() {
        if (player.hasVideo && player.source != "") {
            player.playbackState == MediaPlayer.PlayingState ? pause() : play()
        } else {
            if (database.lastPlayedFile) {
                movieInfo.movie_file = database.lastPlayedFile
                notifybar.show(dsTr("Play last movie played"))
            } else {
                controlbar.reset()
            }
        }
    }

    function forwardByDelta(delta) {
        var tempRate = player.playbackRate
        player.playbackRate = 1.0
        player.seek(player.position + delta)
        notifybar.show(dsTr("Forward to ") + formatTime(player.position) + "  %1%".arg(Math.floor(player.position / (movieInfo.movie_duration + 1) * 100)))
        player.playbackRate = tempRate
    }

    function backwardByDelta(delta) {
        var tempRate = player.playbackRate
        player.playbackRate = 1.0
        player.seek(player.position - delta)
        notifybar.show(dsTr("Rewind to ") + formatTime(player.position) + "  %1%".arg(Math.floor(player.position / (movieInfo.movie_duration + 1) * 100)))
        player.playbackRate = tempRate
    }

    function forward() { forwardByDelta(Math.floor(config.playerForwardRewindStep * 1000)) }
    function backward() { backwardByDelta(Math.floor(config.playerForwardRewindStep * 1000)) }

    function speedUp() { 
        player.playbackRate = Math.min(2.0, (player.playbackRate + 0.1).toFixed(1))
        notifybar.show(dsTr("Playback rate: ") + player.playbackRate + dsTr("(Press %1 to restore)").arg(config.hotkeysPlayRestoreSpeed))
    }

    function slowDown() { 
        player.playbackRate = Math.max(0.1, (player.playbackRate - 0.1).toFixed(1))
        notifybar.show(dsTr("Playback rate: ") + player.playbackRate + dsTr("(Press %1 to restore)").arg(config.hotkeysPlayRestoreSpeed))
    }

    function restoreSpeed() {
        player.playbackRate = 1
        notifybar.show(dsTr("Playback rate: ") + player.playbackRate)
    }

    function increaseVolumeByDelta(delta) { setVolume(Math.min(player.volume + delta, 1.0)) }
    function decreaseVolumeByDelta(delta) { setVolume(Math.max(player.volume - delta, 0.0)) }

    function increaseVolume() { increaseVolumeByDelta(0.05) }
    function decreaseVolume() { decreaseVolumeByDelta(0.05) }

    function setVolume(volume) {
        config.playerVolume = volume
        config.playerMuted = false
        notifybar.show(dsTr("Volume: ") + Math.round(player.volume * 100) + "%")
    }

    function setMute(muted) {
        config.playerMuted = muted

        if (player.muted) {
            notifybar.show(dsTr("Muted"))
        } else {
            notifybar.show(dsTr("Volume: ") + Math.round(player.volume * 100) + "%")
        }
    }

    function toggleMute() {
        setMute(!player.muted)
    }

    function openFile() { open_file_dialog.purpose = purposes.openVideoFile; open_file_dialog.open() }
    function openDir() { open_folder_dialog.open() }
    function openFileForPlaylist() { open_file_dialog.purpose = purposes.addPlayListItem; open_file_dialog.open() }
    function openFileForSubtitle() { open_file_dialog.purpose = purposes.openSubtitleFile; open_file_dialog.open() }

    function playNext() { 
        var next = null

        if (config.playerPlayOrderType == "ORDER_TYPE_RANDOM") {
            next = playlist.getRandom()
        } else if (config.playerPlayOrderType == "ORDER_TYPE_RANDOM_IN_ORDER") {
            next = playlist.getNextSource(database.lastPlayedFile)
        } else if (config.playerPlayOrderType == "ORDER_TYPE_SINGLE") {
            next = null
        } else if (config.playerPlayOrderType == "ORDER_TYPE_SINGLE_CYCLE") {
            next = database.lastPlayedFile
        } else if (config.playerPlayOrderType == "ORDER_TYPE_PLAYLIST_CYCLE") {
            next = playlist.getNextSourceCycle(database.lastPlayedFile)
        }

        next ? (movieInfo.movie_file = next) : root.reset()
    }
    function playPrevious() { 
        var next = null

        if (config.playerPlayOrderType == "ORDER_TYPE_RANDOM") {
            next = playlist.getRandom()
        } else if (config.playerPlayOrderType == "ORDER_TYPE_RANDOM_IN_ORDER") {
            next = playlist.getPreviousSource(database.lastPlayedFile)
        } else if (config.playerPlayOrderType == "ORDER_TYPE_SINGLE") {
            next = null
        } else if (config.playerPlayOrderType == "ORDER_TYPE_SINGLE_CYCLE") {
            next = database.lastPlayedFile
        } else if (config.playerPlayOrderType == "ORDER_TYPE_PLAYLIST_CYCLE") {
            next = playlist.getPreviousSourceCycle(database.lastPlayedFile)
        }

        next ? (movieInfo.movie_file = next) : root.reset()
    }

    function setSubtitleVerticalPosition(percentage) {
        config.subtitleVerticalPosition = Math.max(0, Math.min(1, percentage))
        player.subtitleVerticalPosition = config.subtitleVerticalPosition
    }

    function subtitleMoveUp() { setSubtitleVerticalPosition(config.subtitleVerticalPosition + 0.05)}
    function subtitleMoveDown() { setSubtitleVerticalPosition(config.subtitleVerticalPosition - 0.05)}
    function subtitleForward() { player.subtitleDelay += 500 }
    function subtitleBackward() { player.subtitleDelay -= 500 }

    Keys.onPressed: keys_responder.respondKey(event)

    onWheel: { 
        if (config.othersWheel) {
            wheel.angleDelta.y > 0 ? increaseVolumeByDelta(wheel.angleDelta.y / 120 * 0.05)
                                    :decreaseVolumeByDelta(-wheel.angleDelta.y / 120 * 0.05)
            controlbar.emulateVolumeButtonHover()
        }
    }

    onPressed: {
        resizeEdge = getEdge(mouse)
        if (resizeEdge != resize_edge.resizeNone) {
            resize_visual.resizeEdge = resizeEdge
        } else {
            var pos = windowView.getCursorPos()

            windowLastX = windowView.x
            windowLastY = windowView.y
            dragStartX = pos.x
            dragStartY = pos.y
        }
    }

    onPositionChanged: {
        playlist.state = "inactive"

        mouse_area.cursorShape = Qt.ArrowCursor
        hide_mouse_timer.restart()

        if (!pressed) {
            changeCursor(getEdge(mouse))

            if (inRectCheck(mouse, Qt.rect(0, 0, main_window.width,
                                           program_constants.titlebarTriggerThreshold))) {
                showControls()
            } else if (inRectCheck(mouse, Qt.rect(0, main_window.height - controlbar.height,
                                                  main_window.width, program_constants.controlbarTriggerThreshold))) {
                showControls()
            }
        /* else if (!playlist.expanded && inRectCheck(mouse,  */
        /*     Qt.rect(main_window.width - program_constants.playlistTriggerThreshold, 0,  */
        /*     program_constants.playlistTriggerThreshold, main_window.height))) { */
        /*     show_playlist_timer.restart() */
        /* } */
        }
        else {
            // prevent play or pause event from happening if we intend to move or resize the window
            shouldPlayOrPause = false
            if (resizeEdge != resize_edge.resizeNone) {
                resize_visual.show()
                resize_visual.intelligentlyResize(windowView, mouse.x, mouse.y)
            }
            else {
                var pos = windowView.getCursorPos()
                windowView.setX(windowLastX + pos.x - dragStartX)
                windowView.setY(windowLastY + pos.y - dragStartY)
                windowLastX = windowView.x
                windowLastY = windowView.y
                dragStartX = pos.x
                dragStartY = pos.y
            }
        }
    }

    onReleased: {
        resizeEdge = resize_edge.resizeNone

        if (resize_visual.visible) {
            hasResized = true
            resize_visual.hide()
            // do the actual resize action
            windowView.setX(resize_visual.frameX)
            windowView.setY(resize_visual.frameY)
            _setSizeForRootWindowWithWidth(resize_visual.frameWidth)
        }
    }

    onClicked: {
        if (mouse.button == Qt.RightButton) {
            _menu_controller.show_menu()
        } else {
            clickCount++
            if (!double_click_check_timer.running) {
                double_click_check_timer.start()
            }
        }
    }

    ResizeVisual {
        id: resize_visual

        // FixMe: we should also count the anchors.leftMaring here;
        frameY: windowView.y
        frameX: windowView.x
        frameWidth: window.width
        frameHeight: window.height
    }

    DropArea {
        anchors.fill: parent

        onPositionChanged: {
            if (drag.x > parent.width - program_constants.playlistWidth) {
                playlist.show()
            }
        }

        onDropped: {
            for (var i = 0; i < drop.urls.length; i++) {
                var file_path = drop.urls[i].substring(7)
                file_path = decodeURIComponent(file_path)

                var file_paths = []
                if (_utils.pathIsDir(file_path)) { 
                    file_paths = _utils.getAllVideoFilesInDir(file_path)
                } else if (_utils.pathIsFile(file_path)) {
                    file_paths.push(file_path)
                }

                var dragInPlaylist = drag.x > parent.width - program_constants.playlistWidth

                for (var j = 0; j < file_paths.length; j++) {
                    if (_utils.fileIsValidVideo(file_paths[j])) {
                        addPlayListItem(file_paths[j])
                    }
                }
                if (!dragInPlaylist && file_paths.length > 0) {
                    if (_utils.fileIsValidVideo(file_paths[0])) {
                        movieInfo.movie_file = file_paths[0]
                    } else {
                        movieInfo.subtitle_file = file_paths[0]
                    }
                    showControls()
                }
            }
        }
    }
}