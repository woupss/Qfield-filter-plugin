import QtQuick
import QtCore
import QtQuick.Controls
import QtQuick.Layouts
import Theme
import org.qfield
import org.qgis
import "qrc:/qml" as QFieldItems

Item {
    id: drivemeTool
    objectName: "driveMe"
    property var mainWindow: iface.mainWindow()
    property var mapCanvas: iface.mapCanvas()
    
    // --- VARIABLES ---
    property var unvisitedPoints: []   
    property var currentTarget: null   
    property int totalPointsCount: 0
    property bool isNavigating: false
    property bool isPaused: false
    
    // HUD (Distance affichée)
    property string distanceText: "-- m"
    property string hudMessage: ""
    property bool hudMessagePersistent: false
    
    // ÉTATS
    property string navState: "DRIVING" 
    property var parkedLocation: null 

    // CONFIG
    property int chainWalkThreshold: 50 
    property var lastProcessPos: null
    property var lastRouteCoords: null
    property bool routeHasFootSegment: false
    property var lastFootPos: null
    property var polygonVertices: ({})
    property var polygonCenters: ({})
    property var traveledCoords: []
    // Zoom GPS + entités filtrées — géré ici, reçu depuis FilterTool
    property real savedZoomHW: 0
    property real savedZoomHH: 0
    property var pendingDriveMeLayer: null
    property var pendingFeatExtent: null

    // --- RAYON DE MARCHE et route piétonne ---
    property real walkRadius: 200           // distance max à pied depuis le parking (mètres)
    property var lastFootRouteCoords: null  // route piétonne — calculée une seule fois
    property bool targetJustValidated: false
    property bool footRoutePending: false

    // --- COULEURS CONFIGURABLES ---
    property string _editingKey: ""

    Settings {
        id: navColorSettings
        category: "DriveMeToolColors"
        property string carColor: "#FF00FF"
        property string footColor:  "#02AE0F" // "#FF9500"
        property string parkColor:   "#00FF00"
        property string targetColor: "#0093FC"
        property string targetgeomColor: "cyan"
    }


    // --- TRADUCTION FR / EN ---
    property string currentLang: "fr"

    function detectLanguage() {
        var loc = Qt.locale().name.substring(0, 2)
        currentLang = (loc === "fr") ? "fr" : "en"
    }

    property var translations: {
        "RESTANT":                               { "fr": "RESTANT",                               "en": "REMAINING" },
        "DISTANCE":                              { "fr": "DISTANCE",                              "en": "DISTANCE" },
        "NAVIGATION":                            { "fr": "NAVIGATION",                            "en": "NAVIGATION" },
        "Couche:":                               { "fr": "Couche :",                              "en": "Layer:" },
        "ARRÊTER":                               { "fr": "ARRÊTER",                               "en": "STOP" },
        "DÉMARRER":                              { "fr": "DÉMARRER",                              "en": "START" },
        "Aucun élément trouvé":                  { "fr": "Aucun élément trouvé",                  "en": "No features found" },
        "Aucun point trouvé":                    { "fr": "Aucun point trouvé",                    "en": "No points found" },
        "Calcul de l'itinéraire en pause":       { "fr": "Calcul de l'itinéraire en pause",       "en": "Calculate way in pause" },
        "Calcul de l'itinéraire activé":         { "fr": "Calcul de l'itinéraire activé",         "en": "Calculate way reactivated" },
        "✅ Cible atteinte !":                   { "fr": "✅ Cible atteinte !",                   "en": "✅ Target reached!" },
        "✅ Point validé\nau passage !":          { "fr": "✅ Point validé\nau passage !",          "en": "✅ Point validated\non the way!" },
        "Retour au véhicule.":                   { "fr": "Retour au véhicule.",                   "en": "Return to vehicle." },
"🔄 Retour voiture :\naccès route plus court(-": { "fr": "🔄 Retour voiture :\naccès route plus court\n(-", "en": "🔄 Return to car:\nshorter road access(-" },
        "🏁 Terminé !":                          { "fr": "🏁 Terminé !",                          "en": "🏁 Done!" },
        "Accès à pied\n(point isolé)":           { "fr": "Accès à pied\n(point isolé)",           "en": "On foot\n(isolated point)" },
        "👟 À pied plus rapide":                 { "fr": "👟 À pied plus rapide",                 "en": "👟 Faster on foot" },
        "🚗 Retour voiture":                     { "fr": "🚗 Retour voiture",                     "en": "🚗 Back to car" },
        "min gagnées":                           { "fr": "min gagnées",                           "en": "min saved" },
        "En route.":                             { "fr": "En route.",                             "en": "Drive on." },
        "Fin de route.\nFinir à pied.":          { "fr": "Fin de route.\nFinir à pied.",          "en": "End of road.\nFinish on foot." },
        "Voiture stationnée.\nFinir à pied.":    { "fr": "Voiture stationnée.\nFinir à pied.",    "en": "Vehicle parked.\nFinish on foot." },
        // Clés pour le dialogue de navigation
        "Vers les géométries de la couche :":    { "fr": "Vers les géométries de la couche :",    "en": "Towards the geometries of layer:" },
        "Code couleur":                          { "fr": "Code couleur",                          "en": "Color code" },
        "Tracé voiture":                         { "fr": "Tracé voiture",                         "en": "Car route" },
        "Tracé piéton":                          { "fr": "Tracé piéton",                          "en": "Walk route" },
        "Stationnement":                         { "fr": "Stationnement",                         "en": "Parking" },
        "Points cibles":                         { "fr": "Points cibles",                         "en": "Target points" },
        "Annuler":                               { "fr": "Annuler",                               "en": "Cancel" },
        "👟 ":                                   { "fr": "👟 ",                                   "en": "👟 " },
        " point(s) dans rayon 200m":             { "fr": " point(s) dans rayon 200m",             "en": " point(s) within 200m" },
        "👟 Plus rapide à pied\n(":              { "fr": "👟 Plus rapide à pied\n(",              "en": "👟 Faster on foot\n(" },
        "m)":                                    { "fr": "m)",                                    "en": "m)" },
        "✅ Rayon terminé.\nRetour véhicule.":   { "fr": "✅ Rayon terminé.\nRetour véhicule.",   "en": "✅ Zone done.\nReturn to vehicle." },
        "🚗 Hors rayon 200m.\nRetour véhicule.":{ "fr": "🚗 Hors rayon 200m.\nRetour véhicule.","en": "🚗 Outside 200m.\nReturn to vehicle." }
    }

    function tr(key) {
        var t = translations[key]
        if (t) return t[currentLang] !== undefined ? t[currentLang] : key
        return key
    }


    // Component.onCompleted: {
   //     iface.addItemToPluginsToolbar(btnNav)
   //     detectLanguage()
    //}

    // --- 1. RENDU ---
    QFieldItems.GeometryRenderer {
        id: carRenderer
        parent: mapCanvas
        mapSettings: mapCanvas.mapSettings
        geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
        lineWidth: 6
        color: navColorSettings.carColor
        opacity: 1.0
    }

    QFieldItems.GeometryRenderer {
        id: footRenderer
        parent: mapCanvas
        mapSettings: mapCanvas.mapSettings
        geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
        lineWidth: 5
        color: navColorSettings.footColor
        opacity: 1.0
    }

    QFieldItems.GeometryRenderer {
        id: onRouteRenderer
        parent: mapCanvas
        mapSettings: mapCanvas.mapSettings
        geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
        lineWidth: 14
        color: navColorSettings.targetColor
        opacity: 1.0
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: isNavigating
            NumberAnimation { from: 0.9; to: 0.1; duration: 500; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.1; to: 0.9; duration: 500; easing.type: Easing.InOutQuad }
        }
    }

    QFieldItems.GeometryRenderer {
        id: polygonCenterRenderer
        parent: mapCanvas
        mapSettings: mapCanvas.mapSettings
        geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
        lineWidth: 4
        color: "cyan" // Fuschia — centre du polygone lié à la cible rouge courante
        opacity: 1.0
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: isNavigating
            NumberAnimation { from: 0.9; to: 0.15; duration: 500; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.15; to: 0.9; duration: 500; easing.type: Easing.InOutQuad }
        }
    }

    QFieldItems.GeometryRenderer {
        id: arrowRenderer
        parent: mapCanvas
        mapSettings: mapCanvas.mapSettings
        geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
        lineWidth: 2
        color: "cyan" // Fuschia fin — flèches sommet rouge → centroïde fuschia
        opacity: 0.75
    }

    // Transformateur GPS WGS84 → CRS carte, pour le zoom position+entités
    CoordinateTransformer {
        id: gpsMapTransformer
        sourceCrs: CoordinateReferenceSystemUtils.wgs84Crs()
        destinationCrs: mapCanvas.mapSettings.destinationCrs
        transformContext: qgisProject ? qgisProject.transformContext
                                      : CoordinateReferenceSystemUtils.emptyTransformContext()
    }

    // --- 2. MARQUEURS ---
    CoordinateTransformer {
        id: targetTransformer
        sourceCrs: CoordinateReferenceSystemUtils.wgs84Crs()
        destinationCrs: mapCanvas.mapSettings.destinationCrs
        transformContext: qgisProject ? qgisProject.transformContext : CoordinateReferenceSystemUtils.emptyTransformContext()
    }
    MapToScreen {
        id: targetScreenPos
        mapSettings: mapCanvas.mapSettings
        mapPoint: targetTransformer.projectedPosition
    }
    Item {
        id: blinkingTarget
        parent: mapCanvas
        visible: isNavigating && currentTarget !== null && navState !== "RETURNING_TO_CAR"
        x: targetScreenPos.screenPoint.x - width / 2
        y: targetScreenPos.screenPoint.y - height / 2
        width: 50; height: 50
        Rectangle { anchors.centerIn: parent; width: 16; height: 16; radius: 8; color: navColorSettings.targetColor; border.color: "white"; border.width: 2 }
        Rectangle {
            anchors.centerIn: parent; width: parent.width; height: parent.height; radius: width / 2; color: "transparent"; border.color: navColorSettings.targetColor; border.width: 3
            SequentialAnimation on scale { loops: Animation.Infinite; running: blinkingTarget.visible; NumberAnimation { from: 0.2; to: 1.0; duration: 1200; easing.type: Easing.OutQuad } }
            SequentialAnimation on opacity { loops: Animation.Infinite; running: blinkingTarget.visible; NumberAnimation { from: 1.0; to: 0.0; duration: 1200; easing.type: Easing.OutQuad } }
        }
    }

    CoordinateTransformer {
        id: carTransformer
        sourceCrs: CoordinateReferenceSystemUtils.wgs84Crs()
        destinationCrs: mapCanvas.mapSettings.destinationCrs
        transformContext: qgisProject ? qgisProject.transformContext : CoordinateReferenceSystemUtils.emptyTransformContext()
    }
    MapToScreen {
        id: carScreenPos
        mapSettings: mapCanvas.mapSettings
        mapPoint: carTransformer.projectedPosition
    }
    Item {
        id: blinkingCar
        parent: mapCanvas
        visible: isNavigating && parkedLocation !== null
        x: carScreenPos.screenPoint.x - width / 2
        y: carScreenPos.screenPoint.y - height / 2
        width: 60; height: 60
        Rectangle { anchors.centerIn: parent; width: 20; height: 20; radius: 10; color: navColorSettings.parkColor; border.color: "black"; border.width: 3 }
        Rectangle {
            anchors.centerIn: parent; width: parent.width; height: parent.height; radius: width / 2; color: "transparent"; border.color: navColorSettings.parkColor; border.width: 4
            SequentialAnimation on scale { loops: Animation.Infinite; running: blinkingCar.visible; NumberAnimation { from: 0.3; to: 1.0; duration: 1500; easing.type: Easing.OutQuad } }
            SequentialAnimation on opacity { loops: Animation.Infinite; running: blinkingCar.visible; NumberAnimation { from: 1.0; to: 0.0; duration: 1500; easing.type: Easing.OutQuad } }
        }
    }

    // --- 3. HUD ---
    Rectangle {
        id: hudBar
        parent: mapCanvas 
        z: 9999
        visible: isNavigating
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: parent.width > parent.height ? 8 : 60
        width: Math.min(parent.width * 0.70, 360) 
        height: 48
        color: "#DD000000" 
        radius: 10
        border.color: "white"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 5
            spacing: 6

            // 1. Compteur de points
            Column {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                Layout.alignment: Qt.AlignVCenter
                Text { text: tr("RESTANT"); color: "#FFFFFF"; font.pixelSize: 10; font.bold: true }
                Text { text: unvisitedPoints.length + " / " + totalPointsCount; color: "#00FF00"; font.pixelSize: 18; font.bold: true }
            }

            Rectangle { width: 1; height: 40; color: "gray"; Layout.alignment: Qt.AlignVCenter }

            // 2. Mode actuel (avec défilement)
            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                Layout.alignment: Qt.AlignVCenter
                height: 40
                clip: true

                Text {
                    id: hudText
                    text: getHudText()
                    color: "white"
                    font.pixelSize: 14
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter

                    SequentialAnimation on x {
                        id: marqueeAnim
                        loops: Animation.Infinite
                        running: hudText.implicitWidth > hudText.parent.width
                        PauseAnimation  { duration: 500 }
                        NumberAnimation {
                            from:     hudText.parent ? hudText.parent.width : 0
                            to:       -(hudText.implicitWidth)
                            duration: hudText.implicitWidth > 0
                                        ? (hudText.implicitWidth + (hudText.parent ? hudText.parent.width : 0)) * 16
                                        : 1
                            easing.type: Easing.Linear
                        }
                    }
                }
            }

            // 3. Distance
            Column {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                Layout.alignment: Qt.AlignVCenter
                Text { text: tr("DISTANCE"); color: "#FFFFFF"; font.pixelSize: 10; font.bold: true }
                Text { text: distanceText; color: "cyan"; font.pixelSize: 18; font.bold: true }
            }

            // Bouton pause/arrêt
            Item {
        Layout.fillWidth: true
        Layout.preferredWidth: 2   // poids = 2 parts (plus petit)
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: parent.height
        QfToolButton {
    anchors.centerIn: parent
    iconSource: "DriveMeicon.svg"
    iconColor: isPaused ? "orange" : "red"
    flat: true

    onClicked: {
        if (!isNavigating) return

        isPaused = !isPaused

        if (isPaused) {
            showHudMessage("Navigation en pause")
        } else {
            showHudMessage("Navigation reprise")
        }
    }

    onPressAndHold: {
        if (!isNavigating) return

        isPaused = false
        stopNavigation()
        showHudMessage("Navigation arrêtée")
                    }
                }
            }
        }
    }

    Timer {
        id: hudMessageTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (!drivemeTool.hudMessagePersistent)
                hudMessage = ""
        }
    }

    Timer {
        id: resetPolygonTimer
        interval: 50        // 50ms — imperceptible mais suffit à reset l'animation
        repeat: false
        onTriggered: {
            updatePolygonCenterRenderer()
        }
    }

    function showHudMessage(text, persistent) {
        hudMessagePersistent = (persistent === true)   
        hudMessage = text
        if (!hudMessagePersistent)
            hudMessageTimer.restart()
        else
            hudMessageTimer.stop()
    }

    function getHudText() {
        if (hudMessage !== "") return hudMessage
        return ""
    }

    // --- 4. TIMER ---
    Timer {
        id: navTimer
        interval: 800
        repeat: true
        running: isNavigating && !isPaused
        onTriggered: updateNavigationLoop()
    }

    // --- ZOOM GPS + ENTITÉS FILTRÉES ---
    Timer {
    id: recenterTimer
    interval: 400
    repeat: false
    onTriggered: {
        try {
            let gpsPt = getCurrentGpsPosition()
            if (!gpsPt) gpsPt = getMapCenter() // Secours si pas de GPS

            if (gpsPt) {
                let gpsGeom = GeometryUtils.createGeometryFromWkt("POINT(" + gpsPt.x + " " + gpsPt.y + ")")
                gpsMapTransformer.sourcePosition = GeometryUtils.centroid(gpsGeom)
                let proj = gpsMapTransformer.projectedPosition

                if (proj && (proj.x !== 0 || proj.y !== 0)) {
                    let featExt = pendingFeatExtent
                    if (featExt) {
                        // Calcul des distances par rapport à ma position pour tout englober
                        let dx = Math.max(Math.abs(proj.x - featExt.xMinimum), Math.abs(proj.x - featExt.xMaximum))
                        let dy = Math.max(Math.abs(proj.y - featExt.yMinimum), Math.abs(proj.y - featExt.yMaximum))
                        
                        // Marge de 20% pour ne pas être collé aux bords
                        dx = dx * 1.2
                        dy = dy * 1.2

                        let screenRatio = mapCanvas.width / (mapCanvas.height > 0 ? mapCanvas.height : 1)
                        if (dx / dy > screenRatio) {
                            dy = dx / screenRatio
                        } else {
                            dx = dy * screenRatio
                        }

                        // Création de la nouvelle emprise centrée sur MOI englobant les CIBLES
                        featExt.xMinimum = proj.x - dx
                        featExt.xMaximum = proj.x + dx
                        featExt.yMinimum = proj.y - dy
                        featExt.yMaximum = proj.y + dy

                        mapCanvas.mapSettings.setExtent(featExt, true)
                    }
                }
            }
        } catch(e) { console.log("Erreur Zoom: " + e) }
        
        // Lance la Phase 2 (Démarrage effectif de la navigation) après un court délai
        startDriveTimer.restart()
    }
}

    Timer {
        id: startDriveTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (pendingDriveMeLayer !== null) {
                startNavigationProcess(pendingDriveMeLayer)
                pendingDriveMeLayer = null
                zoomToGpsTimer.restart()
            }
        }
    }

    Timer {
        id: zoomToGpsTimer
        interval: 2000
        repeat: false
        onTriggered: {
            try {
                let gpsPt = getCurrentGpsPosition()
                if (gpsPt) {
                    let gpsGeom = GeometryUtils.createGeometryFromWkt(
                        "POINT(" + gpsPt.x + " " + gpsPt.y + ")")
                    if (gpsGeom) {
                        gpsMapTransformer.sourcePosition = GeometryUtils.centroid(gpsGeom)
                        let proj = gpsMapTransformer.projectedPosition
                        if (proj && (proj.x !== 0 || proj.y !== 0)) {
                            let ext = mapCanvas.mapSettings.extent
                            let destCrs = mapCanvas.mapSettings.destinationCrs
                            let zoomRadius = 300
                            if (destCrs && destCrs.isGeographic) {
                                zoomRadius = 0.0027
                            }
                            let screenRatio = mapCanvas.width / (mapCanvas.height > 0 ? mapCanvas.height : 1)
                            let hw = zoomRadius
                            let hh = zoomRadius / screenRatio
                            ext.xMinimum = proj.x - hw
                            ext.xMaximum = proj.x + hw
                            ext.yMinimum = proj.y - hh
                            ext.yMaximum = proj.y + hh
                            mapCanvas.mapSettings.setExtent(ext, true)
                        }
                    }
                }
            } catch(e) {}
        }
    }

    // --- 5. POINT D'ENTRÉE EXTERNE ---
    // Appelé par FilterTool via iface.findItemByObjectName("driveMe")
    function startWithLayer(layer) {
        if (layer) {
            startNavigationProcess(layer)
        }
    }

    // Point d'entrée depuis FilterTool quand "Filter & Drive me" est activé.
    function startWithLayerAndExtent(layer, featExtent) {
        if (!layer) return
        pendingDriveMeLayer = layer
        pendingFeatExtent   = featExtent
        recenterTimer.restart()
    }


    // --- 5d. FONCTIONS DIALOGUE ---
    function updateLayers() {
        let layers = ProjectUtils.mapLayers(qgisProject)
        let list = []
        for (let id in layers) {
            let l = layers[id]
            if (l && l.type === 0) list.push(l.name)
        }
        list.sort()
        layerSelector.model = list
        if (list.length > 0) layerSelector.currentIndex = 0
    }

    function getLayerByName(name) {
        let layers = ProjectUtils.mapLayers(qgisProject)
        for (let id in layers) { if (layers[id].name === name) return layers[id] }
        return null
    }

    // --- 6. NAVIGATION ---
    function stopNavigation() {
        isNavigating = false
        isPaused = false

        hudMessagePersistent = false
        hudMessage = ""

        let empty = GeometryUtils.createGeometryFromWkt("LINESTRING(0 0, 0.000001 0.000001)")
        if(empty) {
            carRenderer.geometryWrapper.qgsGeometry = empty
            footRenderer.geometryWrapper.qgsGeometry = empty
            onRouteRenderer.geometryWrapper.qgsGeometry = empty
            polygonCenterRenderer.geometryWrapper.qgsGeometry = empty
            arrowRenderer.geometryWrapper.qgsGeometry = empty
        }
        let emptyPoint = GeometryUtils.createGeometryFromWkt("POINT(0 0)")
        if (emptyPoint) {
            carTransformer.sourcePosition = GeometryUtils.centroid(emptyPoint)
        }
        lastRouteCoords = null
        routeHasFootSegment = false
        lastFootPos = null
        lastFootRouteCoords = null
        footRoutePending = false
        polygonVertices = {}
        polygonCenters = {}
        traveledCoords = []

        mapCanvas.refresh()
    }

    function startNavigationProcess(layer) {
        try {
            chainWalkThreshold = 50

            let preSelected = layer.selectedFeatures()
            let hasPreSelection = preSelected && preSelected.length > 0
            
            let feats = []

            if (hasPreSelection) {
                feats = preSelected
            } else {
                layer.selectAll()
                feats = layer.selectedFeatures()
                layer.removeSelection()
            }

            if (!feats || feats.length === 0) { showHudMessage(tr("Aucun élément trouvé")); return }

            if (hasPreSelection) {
                layer.removeSelection()
                let startPos = getCurrentGpsPosition()
                if (!startPos) startPos = getMapCenter()
                let rawPoints = resolvePolygonBoundaryPoints(feats, layer, startPos)
                if (rawPoints.length < 1) { showHudMessage(tr("Aucun point trouvé")); return }
                proceedWithNavigation(rawPoints)
            } else {
                let rawPoints = []
                for (let i = 0; i < feats.length; i++) {
                    let g = feats[i].geometry
                    if (g) {
                        let pt = GeometryUtils.centroid(g)
                        if (pt) {
                            let wgs = GeometryUtils.reprojectPointToWgs84(pt, layer.crs)
                            if (wgs) rawPoints.push({ id: i, x: wgs.x, y: wgs.y })
                        }
                    }
                }
                if (rawPoints.length < 1) { showHudMessage(tr("Aucun point trouvé")); return }
                proceedWithNavigation(rawPoints)
            }

        } catch(e) {}
    }

    // --- OPTION B : sommet du polygone le plus proche de la route/parking, sinon de la position ---
    function resolvePolygonBoundaryPoints(feats, layer, refPos) {
        let rawPoints = []
        let hasRoute = lastRouteCoords && lastRouteCoords.length >= 2
        let hasParking = parkedLocation && parkedLocation.x

        for (let i = 0; i < feats.length; i++) {
            let g = feats[i].geometry
            if (!g) continue

            let centPt = GeometryUtils.centroid(g)
            if (!centPt) continue
            let wgsFallback = GeometryUtils.reprojectPointToWgs84(centPt, layer.crs)
            if (!wgsFallback) continue
            let fallback = { id: i, x: wgsFallback.x, y: wgsFallback.y, onRoute: false }

            try {
                let innerPt = GeometryUtils.pointOnSurface ? GeometryUtils.pointOnSurface(g) : null
                let innerWgs = innerPt ? GeometryUtils.reprojectPointToWgs84(innerPt, layer.crs) : null
                polygonCenters[i] = innerWgs ? { x: innerWgs.x, y: innerWgs.y } : { x: wgsFallback.x, y: wgsFallback.y }
            } catch(e) {
                polygonCenters[i] = { x: wgsFallback.x, y: wgsFallback.y }
            }

            try {
                let wkt = g.asWkt()
                let coords = parseOuterRingCoords(wkt)
                if (!coords || coords.length < 2) { rawPoints.push(fallback); continue }

                let vertices = []
                for (let j = 0; j < coords.length; j++) {
                    let vWkt = "POINT(" + coords[j][0] + " " + coords[j][1] + ")"
                    let vGeom = GeometryUtils.createGeometryFromWkt(vWkt)
                    if (!vGeom) continue
                    let vPt = GeometryUtils.centroid(vGeom)
                    if (!vPt) continue
                    let vWgs = GeometryUtils.reprojectPointToWgs84(vPt, layer.crs)
                    if (!vWgs) continue
                    vertices.push({ x: vWgs.x, y: vWgs.y })
                }
                if (vertices.length === 0) { rawPoints.push(fallback); continue }

                polygonVertices[i] = vertices

                let bestPt = null
                let bestDist = 1e9

                if (hasParking) {
                    for (let k = 0; k < vertices.length; k++) {
                        let dParking = getDistMeters(parkedLocation, vertices[k])
                        let dRoute = hasRoute ? minDistToRouteLine(vertices[k], lastRouteCoords) : 0
                        let d = dParking + dRoute
                        if (d < bestDist) { bestDist = d; bestPt = vertices[k] }
                    }
                } else if (hasRoute) {
                    for (let k = 0; k < vertices.length; k++) {
                        let d = minDistToRouteLine(vertices[k], lastRouteCoords)
                        if (d < bestDist) { bestDist = d; bestPt = vertices[k] }
                    }
                    if (bestDist > 200) {
                        bestDist = 1e9; bestPt = null
                        for (let k = 0; k < vertices.length; k++) {
                            let d = getDistMeters(refPos || fallback, vertices[k])
                            if (d < bestDist) { bestDist = d; bestPt = vertices[k] }
                        }
                    }
                } else {
                    for (let k = 0; k < vertices.length; k++) {
                        let d = getDistMeters(refPos || fallback, vertices[k])
                        if (d < bestDist) { bestDist = d; bestPt = vertices[k] }
                    }
                }

                if (!bestPt) { rawPoints.push(fallback); continue }

                let isOnRoute = hasRoute ? (minDistToRouteLine(bestPt, lastRouteCoords) < 20) : false
                let isIsolated = hasRoute && bestDist > 200
                rawPoints.push({ id: i, x: bestPt.x, y: bestPt.y, onRoute: isOnRoute, isolated: isIsolated })

            } catch(e) {
                rawPoints.push(fallback)
            }
        }
        chainIsolatedPoints(rawPoints)
        return rawPoints
    }

    function minDistToRouteLine(pt, routeCoords) {
        let coords = routeCoords || lastRouteCoords
        if (!coords || coords.length < 2) return 1e9
        let minD = 1e9
        for (let i = 0; i < coords.length - 1; i++) {
            let a = { x: coords[i][0],   y: coords[i][1] }
            let b = { x: coords[i+1][0], y: coords[i+1][1] }
            let d = distPointToSegmentMeters(pt, a, b)
            if (d < minD) minD = d
        }
        let last = { x: coords[coords.length-1][0], y: coords[coords.length-1][1] }
        let dLast = getDistMeters(pt, last)
        if (dLast < minD) minD = dLast
        return minD
    }

    function distPointToSegmentMeters(pt, a, b) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if (lenSq < 1e-12) return getDistMeters(pt, a)
        let t = ((pt.x - a.x) * dx + (pt.y - a.y) * dy) / lenSq
        t = Math.max(0, Math.min(1, t))
        let proj = { x: a.x + t * dx, y: a.y + t * dy }
        return getDistMeters(pt, proj)
    }

    function minDistToRoute(pt) {
        return minDistToRouteLine(pt, lastRouteCoords)
    }

    function updateOnRouteRenderer() {
        let onRoutePts = unvisitedPoints.filter(function(p) { return p.onRoute })
        if (onRoutePts.length === 0) {
            clearGeometry(onRouteRenderer)
            return
        }
        let pts = []
        for (let i = 0; i < onRoutePts.length; i++) {
            pts.push(onRoutePts[i].x.toFixed(6) + " " + onRoutePts[i].y.toFixed(6))
        }
        let wkt = "MULTIPOINT(" + pts.join(",") + ")"
        let geom = GeometryUtils.createGeometryFromWkt(wkt)
        if (geom) onRouteRenderer.geometryWrapper.qgsGeometry = geom
    }

    function parseOuterRingCoords(wkt) {
        try {
            let cleaned = wkt.replace(/^MULTIPOLYGON\s*\(\s*\(\s*\(/, "((")
                              .replace(/^POLYGON\s*\(/, "(")
            let match = cleaned.match(/\(([^)]+)\)/)
            if (!match) return null
            let pairs = match[1].trim().split(",")
            let coords = []
            for (let i = 0; i < pairs.length; i++) {
                let parts = pairs[i].trim().split(/\s+/)
                if (parts.length >= 2) {
                    let x = parseFloat(parts[0])
                    let y = parseFloat(parts[1])
                    if (!isNaN(x) && !isNaN(y)) coords.push([x, y])
                }
            }
            return coords.length >= 2 ? coords : null
        } catch(e) { return null }
    }

    function proceedWithNavigation(rawPoints) {
        if (rawPoints.length < 1) { showHudMessage(tr("Aucun point trouvé")); return }

        unvisitedPoints = rawPoints
        totalPointsCount = rawPoints.length
        
        let startPos = getCurrentGpsPosition()
        if (!startPos) startPos = getMapCenter() 
        if (!startPos) startPos = rawPoints[0]
        
        currentTarget = getClosestPoint(startPos, unvisitedPoints).point
        navState = "DRIVING"
        parkedLocation = null
        isNavigating = true
        lastProcessPos = null
        lastFootRouteCoords = null
        footRoutePending = false
        
        if (unvisitedPoints.length >= 2 && unvisitedPoints.length < 50) {
            optimizeEntireTour(startPos)
        }
        
        updateNavigationLoop()
    }

    function optimizeEntireTour(startPos) {
        let coords = startPos.x.toFixed(6) + "," + startPos.y.toFixed(6) + ";"
        coords += unvisitedPoints.map(p => p.x.toFixed(6) + "," + p.y.toFixed(6)).join(";")
        
        let url = "https://routing.openstreetmap.de/routed-car/trip/v1/driving/" + coords + "?source=first"
        
        var xhrTrip = new XMLHttpRequest()
        xhrTrip.onreadystatechange = function() {
            if (xhrTrip.readyState === XMLHttpRequest.DONE && xhrTrip.status === 200) {
                try {
                    let json = JSON.parse(xhrTrip.responseText)
                    if (json.waypoints) {
                        let newOrder = []
                        let waypoints = json.waypoints.sort((a,b) => a.waypoint_index - b.waypoint_index)
                        for (let i = 0; i < waypoints.length; i++) {
                            let idx = waypoints[i].location_index
                            if (idx > 0) newOrder.push(unvisitedPoints[idx - 1])
                        }
                        if (newOrder.length === unvisitedPoints.length) {
                            unvisitedPoints = newOrder
                            currentTarget = unvisitedPoints[0]
                        }
                    }
                } catch(e) {}
            }
        }
        xhrTrip.open("GET", url)
        xhrTrip.send()
    }

    function getClosestPoint(pos, pointsArray) {
        if (!pointsArray || pointsArray.length === 0) return null
        let minDist = 1e9
        let closest = null
        for (let i = 0; i < pointsArray.length; i++) {
            let pt = pointsArray[i]
            let d = getDistMeters(pos, pt)
            if (d < minDist) { minDist = d; closest = pt }
        }
        return { point: closest, distance: minDist }
    }

    function pickBestVertex(pt) {
        let verts = polygonVertices[pt.id]
        if (!verts || verts.length === 0) return pt

        let refCoords = null
        if (lastRouteCoords && lastRouteCoords.length >= 2) {
            refCoords = lastRouteCoords
        } else if (traveledCoords && traveledCoords.length >= 2) {
            refCoords = traveledCoords.map(function(p) { return [p.x, p.y] })
        }
        if (!refCoords) return pt

        let bestPt = null
        let bestDist = 1e9
        for (let k = 0; k < verts.length; k++) {
            let d = minDistToRouteLine(verts[k], refCoords)
            if (d < bestDist) { bestDist = d; bestPt = verts[k] }
        }
        if (!bestPt) return pt
        return { id: pt.id, x: bestPt.x, y: bestPt.y, onRoute: bestDist < 20, isolated: pt.isolated }
    }

    // --- 8. BOUCLE PRINCIPALE ---
    function updateNavigationLoop() {
        if (!isNavigating || isPaused) return

        let myPos = getCurrentGpsPosition()
        if (!myPos) myPos = getCrosshairPosition()
        if (!myPos) return

        let crosshairPos = getCrosshairPosition()
        let routePos = (crosshairPos && getDistMeters(myPos, crosshairPos) > 20) ? crosshairPos : myPos

        // --- ENREGISTREMENT DU TRAJET PARCOURU ---
        if (navState === "DRIVING") {
            let lastTraveled = traveledCoords.length > 0 ? traveledCoords[traveledCoords.length - 1] : null
            if (!lastTraveled || getDistMeters(myPos, lastTraveled) > 15) {
                traveledCoords.push({ x: myPos.x, y: myPos.y })
            }
        }

        // --- CALCUL DE LA DISTANCE POUR LE HUD ---
        let targetDist = 0
        if (navState === "RETURNING_TO_CAR" && parkedLocation) {
            targetDist = getDistMeters(routePos, parkedLocation)
        } else if (currentTarget) {
            targetDist = getDistMeters(routePos, currentTarget)
        }
        
        if (targetDist > 1000) {
            distanceText = (targetDist / 1000).toFixed(1) + " km"
        } else if (targetDist > 0) {
            distanceText = Math.round(targetDist) + " m"
        } else {
            distanceText = "-- m"
        }

        // FLYBY Validation
        let targetWasValidated = false
        let remainingPoints = []
        let flybyRadius = (navState === "DRIVING" || navState === "RETURNING_TO_CAR") ? 15 : 10

        for (let i = 0; i < unvisitedPoints.length; i++) {
            let pt = unvisitedPoints[i]

            // Vérifier la distance au point représentatif
            let nearNow = getDistMeters(myPos, pt) <= flybyRadius
                       || (crosshairPos && getDistMeters(crosshairPos, pt) <= flybyRadius)

            // Vérifier aussi tous les sommets du polygone de la géométrie
            if (!nearNow) {
                let verts = polygonVertices[pt.id]
                if (verts && verts.length > 0) {
                    for (let v = 0; v < verts.length; v++) {
                        if (getDistMeters(myPos, verts[v]) <= flybyRadius
                            || (crosshairPos && getDistMeters(crosshairPos, verts[v]) <= flybyRadius)) {
                            nearNow = true
                            break
                        }
                    }
                }
            }

            let nearTraveled = false
            if (!nearNow && pt.onRoute) {
                for (let t = 0; t < traveledCoords.length; t++) {
                    if (getDistMeters(traveledCoords[t], pt) <= flybyRadius) {
                        nearTraveled = true
                        break
                    }
                    // Vérifier aussi les sommets pour le trajet parcouru
                    let verts = polygonVertices[pt.id]
                    if (verts && verts.length > 0) {
                        for (let v = 0; v < verts.length; v++) {
                            if (getDistMeters(traveledCoords[t], verts[v]) <= flybyRadius) {
                                nearTraveled = true
                                break
                            }
                        }
                    }
                    if (nearTraveled) break
                }
            }
            if (nearNow || nearTraveled) {
                if (currentTarget && pt.id === currentTarget.id) {
                    targetWasValidated = true
                    showHudMessage(tr("✅ Cible atteinte !"), true)
                    if (navState === "DRIVING") {
                        let nextPts = unvisitedPoints.filter(function(p) { return p.id !== pt.id })
                        let needsPark = shouldParkHere(routePos, nextPts)
                        if (needsPark) {
                            parkedLocation = { x: routePos.x, y: routePos.y }
                            lastFootRouteCoords = null; footRoutePending = false
                        }
                    }
                } else {
                    showHudMessage(tr("✅ Point validé\nau passage !"), true)
                }
            } else {
                remainingPoints.push(pt)
            }
        }
        unvisitedPoints = remainingPoints
        // Signaler la validation pour forcer le redémarrage visuel
        if (targetWasValidated) {
            targetJustValidated = true
        }
        updateOnRouteRenderer()
        updatePolygonCenterRenderer()
        updateArrowRenderer()

        // TRANSITIONS
        if (unvisitedPoints.length === 0) {
            if (parkedLocation && navState !== "RETURNING_TO_CAR") {
                navState = "RETURNING_TO_CAR"
                showHudMessage(tr("Retour au v����hicule."))
            } else if (navState !== "RETURNING_TO_CAR") {
                stopNavigation()
                showHudMessage(tr("🏁 Terminé !"), true)
                return
            }
        } 
        else if (targetWasValidated || !currentTarget || !unvisitedPoints.find(p => p.id === currentTarget.id)) {
            if (parkedLocation) {

                // 1. Points isolés dans le rayon du parking (priorité absolue)
                let isolatedInRadius = getPointsInWalkRadius(parkedLocation, unvisitedPoints)
                    .filter(function(p) { return p.isolated })
                    .sort(function(a, b) {
                        return getDistMeters(routePos, a) - getDistMeters(routePos, b)
                    })

                if (isolatedInRadius.length > 0) {
                    // Des points isolés restent dans le rayon → on enchaîne directement
                    currentTarget = isolatedInRadius[0]
                    lastFootRouteCoords = null
                    lastFootPos = null
                    footRoutePending = false
                    navState = "WALKING_TO_POI"
                    targetJustValidated = false  // ← reset du flag
                    updatePolygonCenterRenderer()
                    updateArrowRenderer()
                    showHudMessage(tr("👟 ") + isolatedInRadius.length + tr(" point(s) dans rayon 200m"), true)
                } else {
                    // 2. Chercher un point non-isolé proche de la position courante
                    //    où marcher est plus rapide que retourner en voiture
                    let walkSpeed  = 1.2
                    let driveSpeed = 8.3
                    let distToParked = getDistMeters(routePos, parkedLocation)
                    let bestWalkTarget = null
                    let bestWalkDist   = 1e9

                    for (let w = 0; w < unvisitedPoints.length; w++) {
                        let candidate = unvisitedPoints[w]
                        let distToCandidate = getDistMeters(routePos, candidate)

                        // Doit être dans le rayon de marche depuis la position courante
                        if (distToCandidate > walkRadius) continue

                        // Temps à pied direct vs retour voiture + conduite
                        let timeWalk = distToCandidate / walkSpeed
                        let driveDistEst = getDistMeters(parkedLocation, candidate) * 1.4
                        let timeCar  = distToParked / walkSpeed + driveDistEst / driveSpeed

                        if (timeWalk < timeCar && distToCandidate < bestWalkDist) {
                            bestWalkDist   = distToCandidate
                            bestWalkTarget = candidate
                        }
                    }

                    if (bestWalkTarget) {
                        // Marcher jusqu'au prochain point est plus rapide que reprendre la voiture
                        let distToTarget = Math.round(getDistMeters(routePos, bestWalkTarget))
                        currentTarget = bestWalkTarget
                        lastFootRouteCoords = null
                        lastFootPos = null
                        targetJustValidated = false
                        footRoutePending = false
                        navState = "WALKING_TO_POI"
                        updatePolygonCenterRenderer()
                        updateArrowRenderer()
                        showHudMessage(tr("👟 Plus rapide à pied\n(") + distToTarget + tr("m)"), true)
                    } else {
                        // Aucun point intéressant à atteindre à pied → retour voiture
                        lastFootRouteCoords = null
                        lastFootPos = null
                        footRoutePending = false
                        navState = "RETURNING_TO_CAR"
                        showHudMessage(tr("✅ Rayon terminé.\nRetour véhicule."), true)
                    }
                }
            } else {
                lastRouteCoords = null
                currentTarget = null
                navState = "DRIVING"
                lastProcessPos = null
                selectNextTarget(routePos, function(bestTarget) {
                    if (navState !== "DRIVING") return
                    if (!bestTarget) return
                    if (!unvisitedPoints.find(function(p) { return p.id === bestTarget.id })) return
                    currentTarget = bestTarget
                    unvisitedPoints = unvisitedPoints.map(function(p) { return p.id === bestTarget.id ? bestTarget : p })
                    updateOnRouteRenderer()
                    targetJustValidated = false
                    updatePolygonCenterRenderer()
                    updateArrowRenderer()
                    mapCanvas.refresh()
                })
            }
        }

        if (unvisitedPoints.length === 0 && navState !== "RETURNING_TO_CAR") return

        // MAJ Marqueurs
        let activeTarget = (navState === "RETURNING_TO_CAR" && parkedLocation) ? parkedLocation : currentTarget
        if (activeTarget && activeTarget.x) {
            let wktTarget = "POINT(" + activeTarget.x + " " + activeTarget.y + ")"
            let g = GeometryUtils.createGeometryFromWkt(wktTarget)
            if(g) targetTransformer.sourcePosition = GeometryUtils.centroid(g)
        }
        if (parkedLocation && parkedLocation.x) {
            let wktCar = "POINT(" + parkedLocation.x + " " + parkedLocation.y + ")"
            let g = GeometryUtils.createGeometryFromWkt(wktCar)
            if(g) carTransformer.sourcePosition = GeometryUtils.centroid(g)
        } else {
            let emptyPoint = GeometryUtils.createGeometryFromWkt("POINT(0 0)")
            if(emptyPoint) carTransformer.sourcePosition = GeometryUtils.centroid(emptyPoint)
        }

        // TRACÉS
        var needsRefresh = false

        if (navState === "RETURNING_TO_CAR") {
            if (!parkedLocation) return
            if (getDistMeters(routePos, parkedLocation) < 20) {
                parkedLocation = null
                navState = "DRIVING"
                lastProcessPos = null
                lastRouteCoords = null
                lastFootPos = null
                lastFootRouteCoords = null
                footRoutePending = false
                showHudMessage(tr("En route."))
                updateNavigationLoop()
                return
            }
            if (!lastFootPos) {
                // Premier tick : lancer fetchFootRoute (qui dessine direct line immédiatement)
                // puis effacer carRenderer seulement après
                lastFootPos = routePos
                fetchFootRoute(routePos, parkedLocation)
             //   clearGeometry(carRenderer)
                needsRefresh = true
            } else if (lastFootRouteCoords) {
                let distFromRoute = getDistMeters(routePos,
                    { x: lastFootRouteCoords[0][0], y: lastFootRouteCoords[0][1] })
                if (distFromRoute > 50) {
                    lastFootRouteCoords = null
                    lastFootPos = routePos
                //    footRoutePending = false
                    fetchFootRoute(routePos, parkedLocation)
                } else if (getDistMeters(routePos, lastFootPos) > 10) {
                    lastFootPos = routePos
                    trimFootRouteToCurrentPos(routePos)
                    needsRefresh = true
                }
            }
        }
        else if (navState === "WALKING_TO_POI") {
            if (!currentTarget) return

            if (parkedLocation) {
                let distFromCar = getDistMeters(parkedLocation, currentTarget)
                if (distFromCar > walkRadius) {
                    lastFootRouteCoords = null
                    lastFootPos = null
                    footRoutePending = false
                    navState = "RETURNING_TO_CAR"
                    showHudMessage(tr("🚗 Hors rayon 200m.\nRetour véhicule."), true)
                    return
                }
            }

            // Effacer le tracé voiture une seule fois à l'entrée dans cet état
            if (!lastFootPos) {
           //     clearGeometry(carRenderer)
                fetchFootRoute(routePos, currentTarget)
                lastFootPos = routePos
                needsRefresh = true
            } else if (lastFootRouteCoords) {
                let distFromRoute = getDistMeters(routePos,
                    { x: lastFootRouteCoords[0][0], y: lastFootRouteCoords[0][1] })
                if (distFromRoute > 50) {
                    // Déviation : recalcul seulement si déplacement significatif
                    lastFootRouteCoords = null
                    lastFootPos = routePos
                    fetchFootRoute(routePos, currentTarget)
                } else if (getDistMeters(routePos, lastFootPos) > 10) {
                    // Trim seulement si déplacement > 10m
                    lastFootPos = routePos
                    trimFootRouteToCurrentPos(routePos)
                    needsRefresh = true
                }
            }
        }
        else if (navState === "DRIVING") {
            if (!currentTarget) return
            if (lastRouteCoords && lastRouteCoords.length >= 2) {
                if (trimRouteToCurrentPos(routePos)) needsRefresh = true
            }
            if (!lastProcessPos || getDistMeters(routePos, lastProcessPos) > 40) {
                lastProcessPos = routePos
                fetchOsrmRoute(routePos, currentTarget)
            }
        }

        if (needsRefresh) mapCanvas.refresh()
    }

    function selectNextTarget(pos, onDone) {
    let snapNavState = navState
    let allVerts = []

    // 1. Collecte de tous les sommets/points
    for (let i = 0; i < unvisitedPoints.length; i++) {
        let pt = unvisitedPoints[i]
        if (pt.isolated) continue // On ignore les points isolés pour le snapping route
        let verts = polygonVertices[pt.id]
        if (verts && verts.length > 0) {
            for (let j = 0; j < verts.length; j++) {
                allVerts.push({ vert: verts[j], ptId: pt.id })
            }
        } else {
            allVerts.push({ vert: { x: pt.x, y: pt.y }, ptId: pt.id })
        }
    }

    if (allVerts.length === 0) {
        let fb = getClosestPoint(pos, unvisitedPoints)
        onDone(fb ? fb.point : null)
        return
    }

    // 2. Appel à Valhalla pour localiser la route la plus proche de chaque point
    let locations = allVerts.map(function(e) { return { lon: e.vert.x, lat: e.vert.y } })
    let body = JSON.stringify({ locations: locations, costing: "auto" })
    let url = "https://valhalla1.openstreetmap.de/locate"

    var req = new XMLHttpRequest()
    req.timeout = 8000
    req.ontimeout = function() {
        let fb = getClosestPoint(pos, unvisitedPoints); onDone(fb ? fb.point : null)
    }
    req.onerror = req.ontimeout
    req.onreadystatechange = function() {
        if (req.readyState !== XMLHttpRequest.DONE) return
        if (navState !== snapNavState) return
        if (req.status === 200) {
            try {
                let json = JSON.parse(req.responseText)
                let bestPerPt = {}

                // On analyse les résultats de Valhalla
                for (let k = 0; k < json.length && k < allVerts.length; k++) {
                    let entry = json[k]
                    let roadDist = 1e9 // Distance entre le point et la route
                    if (entry && entry.edges && entry.edges.length > 0) {
                        let edge = entry.edges[0]
                        if (edge.correlated_lat !== undefined && edge.correlated_lon !== undefined) {
                            roadDist = getDistMeters(
                                allVerts[k].vert,
                                { x: edge.correlated_lon, y: edge.correlated_lat }
                            )
                        }
                    }
                    let ptId = allVerts[k].ptId
                    if (!bestPerPt[ptId] || roadDist < bestPerPt[ptId].roadDist) {
                        bestPerPt[ptId] = { vert: allVerts[k].vert, roadDist: roadDist }
                    }
                }

                // --- LOGIQUE D'OPTIMISATION DU SCORE ---
                let bestTarget = null
                let bestScore = 1e9

                for (let ptId in bestPerPt) {
                    let b = bestPerPt[ptId]
                    let distToMe = getDistMeters(pos, b.vert)
                    
                    /**
                     * CALCUL DU SCORE INTELLIGENT :
                     * On veut minimiser : Distance_GPS + (Distance_à_la_route * Facteur)
                     * 
                     * - Si b.roadDist est petit (< 30m) : le point est "en bord de route". Très attractif.
                     * - Si b.roadDist est grand (> 200m) : le point demande une longue marche. 
                     *   On lui donne une forte pénalité pour ne pas le choisir maintenant, 
                     *   sauf si on est déjà garé juste à côté.
                     */
                    for (let k = 0; k < json.length && k < allVerts.length; k++) {
                    let entry = json[k]
                    let roadDist = 1e9
                    let roadSpeed = 50  // valeur par défaut urbaine
                    if (entry && entry.edges && entry.edges.length > 0) {
                        let edge = entry.edges[0]
                        if (edge.correlated_lat !== undefined && edge.correlated_lon !== undefined) {
                            roadDist = getDistMeters(
                                allVerts[k].vert,
                                { x: edge.correlated_lon, y: edge.correlated_lat }
                            )
                        }
                        // Récupérer la vitesse de la route
                        if (edge.speed !== undefined) {
                            roadSpeed = edge.speed
                        } else if (edge.road_class !== undefined) {
                            // Estimation par classe si speed absent
                            let rc = edge.road_class
                            if (rc === "motorway")  roadSpeed = 130
                            else if (rc === "trunk") roadSpeed = 110
                            else if (rc === "primary") roadSpeed = 90
                            else roadSpeed = 50
                        }
                    }
                    let ptId = allVerts[k].ptId
                    if (!bestPerPt[ptId] || roadDist < bestPerPt[ptId].roadDist) {
                        bestPerPt[ptId] = { vert: allVerts[k].vert, roadDist: roadDist, roadSpeed: roadSpeed }
                    }
                }

let roadPenalty = 0
                    if (b.roadDist > 50) {
                        roadPenalty = b.roadDist * 5
                    }

                    // Pénalité voie rapide > 90km/h
                    // On préfère largement un point à 200m d'une route normale
                    // plutôt qu'un point à 20m d'une autoroute
                    let speedPenalty = 0
                    let speed = b.roadSpeed || 50
                    if (speed > 110) {
                        speedPenalty = 100000  // autoroute/voie express → quasi-exclusion
                    } else if (speed > 90) {
                        speedPenalty = 5000    // route nationale rapide → forte pénalité
                    }

                    let currentScore = distToMe + roadPenalty + speedPenalty


                    if (currentScore < bestScore) {
                        bestScore = currentScore
                        let pt = unvisitedPoints.find(p => p.id === parseInt(ptId) || p.id === ptId)
                        if (pt) {
                            bestTarget = { 
                                id: pt.id, 
                                x: b.vert.x, 
                                y: b.vert.y, 
                                onRoute: b.roadDist < 30, // Taggué comme "accessible voiture" si < 30m
                                roadDist: b.roadDist,      // On stocke la distance pour usage ultérieur
                                isolated: pt.isolated 
                            }
                        }
                    }
                }

                if (!bestTarget) {
                    let fb = getClosestPoint(pos, unvisitedPoints)
                    bestTarget = fb ? fb.point : null
                }

                onDone(bestTarget)
                return
            } catch(e) { console.log("Erreur parsing Valhalla: " + e) }
        }
        let fb = getClosestPoint(pos, unvisitedPoints); onDone(fb ? fb.point : null)
    }
    req.open("POST", url)
    req.setRequestHeader("Content-Type", "application/json")
    req.send(body)
}

    function checkAlternativeFootAccess(target, currentWalkDist, onResult) {
    let verts = polygonVertices[target.id]
    if (!verts || verts.length === 0) { onResult(currentWalkDist, null); return }

    let locations = verts.map(function(v) { return { lon: v.x, lat: v.y } })
    let body = JSON.stringify({ locations: locations, costing: "auto" })

    var req = new XMLHttpRequest()
    req.timeout = 5000
    req.ontimeout = function() { onResult(currentWalkDist, null) }
    req.onerror   = req.ontimeout
    req.onreadystatechange = function() {
        if (req.readyState !== XMLHttpRequest.DONE) return
        if (req.status === 200) {
            try {
                let json = JSON.parse(req.responseText)
                let bestRoadDist = 1e9
                let bestVert = null
                for (let k = 0; k < json.length && k < verts.length; k++) {
                    let entry = json[k]
                    if (entry && entry.edges && entry.edges.length > 0) {
                        let edge = entry.edges[0]
                        if (edge.correlated_lat !== undefined && edge.correlated_lon !== undefined) {
                            let rd = getDistMeters(verts[k],
                                { x: edge.correlated_lon, y: edge.correlated_lat })
                            if (rd < bestRoadDist) { bestRoadDist = rd; bestVert = verts[k] }
                        }
                    }
                }
                onResult(bestRoadDist, bestVert); return
            } catch(e) {}
        }
        onResult(currentWalkDist, null)
    }
    req.open("POST", "https://valhalla1.openstreetmap.de/locate")
    req.setRequestHeader("Content-Type", "application/json")
    req.send(body)
}

    // --- Retourne tous les points dans le rayon walkRadius depuis parkPos ---
    function getPointsInWalkRadius(parkPos, points) {
        if (!parkPos || !points) return []
        return points.filter(function(p) {
            return getDistMeters(parkPos, p) <= walkRadius
        })
    }

    // --- Routage piéton Valhalla — calcul unique, fallback ligne droite ---
    function valhallaFootRequest(start, end, callback) {
        let straightDist = getDistMeters(start, end)
        let url = "https://valhalla1.openstreetmap.de/route"
        let body = JSON.stringify({
            locations: [
                { lon: start.x, lat: start.y, type: "break" },
                { lon: end.x,   lat: end.y,   type: "break" }
            ],
            costing: "pedestrian",
            costing_options: {
                pedestrian: {
                    use_ferry:          0.0,
                    use_living_streets: 1.0,
                    use_tracks:         1.0,
                    use_hills:          0.5,
                    service_penalty:    0.0,
                    walkway_factor:     0.8
                }
            },
            directions_options: { units: "kilometers" }
        })
        var req = new XMLHttpRequest()
        req.timeout = 5000
        req.ontimeout = function() { callback(null) }
        req.onerror   = function() { callback(null) }
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            if (req.status === 200) {
                try {
                    let json = JSON.parse(req.responseText)
                    if (json.trip && json.trip.legs && json.trip.legs.length > 0) {
                        let coords = decodePolyline6(json.trip.legs[0].shape)
                        if (coords && coords.length >= 2) {
                            // Rejeter les détours absurdes (> 4× la distance directe)
                            let routeDist = 0
                            for (let i = 0; i < coords.length - 1; i++) {
                                routeDist += getDistMeters(
                                    { x: coords[i][0],   y: coords[i][1] },
                                    { x: coords[i+1][0], y: coords[i+1][1] }
                                )
                            }
             if (routeDist <= straightDist * 2.5) {
                                callback(coords)
                                return
                            }
                        }
                    }
                } catch(e) {}
            }
            callback(null) // fallback → ligne droite dans fetchFootRoute
        }
        req.open("POST", url)
        req.setRequestHeader("Content-Type", "application/json")
        req.send(body)
    }

    // --- Calcule la route piétonne UNE SEULE FOIS et la stocke ---
    function fetchFootRoute(start, end) {
        drawDirectLine(start, end, footRenderer)
        clearGeometry(carRenderer)
        mapCanvas.refresh()
        valhallaFootRequest(start, end, function(coords) {
            if (navState !== "WALKING_TO_POI" && navState !== "RETURNING_TO_CAR") return
            footRoutePending = false
            if (coords && coords.length >= 2) {
                // Vérifier que le chemin Valhalla ne repart pas en arrière
                // En comparant la distance du 2ème point vers la cible
                // vs la distance du départ vers la cible
                let distStartToEnd = getDistMeters(start, end)
                let secondPt = { x: coords[1][0], y: coords[1][1] }
                let distSecondToEnd = getDistMeters(secondPt, end)

                // Si le 2ème point s'éloigne de la cible → chemin part en arrière → ligne droite
                if (distSecondToEnd > distStartToEnd + 15) {
                    lastFootRouteCoords = null
                    drawDirectLine(start, end, footRenderer)
                    mapCanvas.refresh()
                    return
                }

                // Chemin valide → forcer départ et arrivée exacts
                coords[0] = [start.x, start.y]
                let snapEnd = { x: coords[coords.length-1][0], y: coords[coords.length-1][1] }
                if (getDistMeters(snapEnd, end) > 5) {
                    coords = coords.concat([[end.x, end.y]])
                }
                lastFootRouteCoords = coords
                drawLineFromCoords(coords, footRenderer)
            } else {
                lastFootRouteCoords = null
                drawDirectLine(start, end, footRenderer)
            }
            mapCanvas.refresh()
        })
    }

    // --- Découpe la route piétonne au fur et à mesure de la progression ---
    function trimFootRouteToCurrentPos(pos) {
        if (!lastFootRouteCoords || lastFootRouteCoords.length < 2) return false
        let minDist = 1e9
        let closestIdx = 0
        for (let i = 0; i < lastFootRouteCoords.length; i++) {
            let d = getDistMeters(pos, { x: lastFootRouteCoords[i][0], y: lastFootRouteCoords[i][1] })
            if (d < minDist) { minDist = d; closestIdx = i }
        }
        if (closestIdx === 0) return false
        lastFootRouteCoords = lastFootRouteCoords.slice(closestIdx)
        if (lastFootRouteCoords.length >= 2)
            drawLineFromCoords(lastFootRouteCoords, footRenderer)
        return true
    }

    // --- 9. ROUTAGE VALHALLA ---
    function fetchOsrmRoute(start, end) {
        let snapNavState = navState
        let snapTarget = currentTarget
        valhallaRequest(start, end, snapNavState, snapTarget, function(coords, snap, distOffRoad) {
            if (navState !== snapNavState || currentTarget !== snapTarget) return
            applyRouteResult(start, end, coords, snap, distOffRoad, snapNavState, snapTarget)
        })
    }

    function decodePolyline6(encoded) {
        let coords = []
        let index = 0, lat = 0, lng = 0
        while (index < encoded.length) {
            let b, shift = 0, result = 0
            do {
                b = encoded.charCodeAt(index++) - 63
                result |= (b & 0x1f) << shift
                shift += 5
            } while (b >= 0x20)
            let dlat = (result & 1) ? ~(result >> 1) : (result >> 1)
            lat += dlat
            shift = 0; result = 0
            do {
                b = encoded.charCodeAt(index++) - 63
                result |= (b & 0x1f) << shift
                shift += 5
            } while (b >= 0x20)
            let dlng = (result & 1) ? ~(result >> 1) : (result >> 1)
            lng += dlng
            coords.push([lng / 1e6, lat / 1e6])
        }
        return coords
    }

    function valhallaRequest(start, end, snapNavState, snapTarget, callback) {
        let url = "https://valhalla1.openstreetmap.de/route"
        let body = JSON.stringify({
            locations: [
                { lon: start.x, lat: start.y, type: "break" },
                { lon: end.x,   lat: end.y,   type: "break" }
            ],
            costing: "auto",
            costing_options: {
                auto: {
                    use_tracks: 1.0,
                    use_roads:  0.8,
                    use_ferry:  0.0,
                    top_speed:  80
                }
            },
            directions_options: { units: "kilometers" }
        })
        var req = new XMLHttpRequest()
        req.timeout = 4000
        req.ontimeout = function() { callback(null, null, 1e9) }
        req.onerror   = function() { callback(null, null, 1e9) }
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE) return
            if (navState !== snapNavState || currentTarget !== snapTarget) return
            if (req.status === 200) {
                try {
                    let json = JSON.parse(req.responseText)
                    if (json.trip && json.trip.legs && json.trip.legs.length > 0) {
                        let coords = decodePolyline6(json.trip.legs[0].shape)
                        if (coords && coords.length >= 2) {
                            let snap = { x: coords[coords.length-1][0], y: coords[coords.length-1][1] }
                            callback(coords, snap, getDistMeters(snap, end))
                            return
                        }
                    }
                } catch(e) {}
            }
            callback(null, null, 1e9)
        }
        req.open("POST", url)
        req.setRequestHeader("Content-Type", "application/json")
        req.send(body)
    }

    function applyRouteResult(start, end, coords, snap, distOffRoad, snapNavState, snapTarget) {
        if (!coords) { drawDirectLine(start, end, carRenderer); return }
        if (navState !== snapNavState || currentTarget !== snapTarget) return
        let extCoords = coords
        if (coords.length >= 2) {
            let p1 = coords[coords.length - 2]
            let p2 = coords[coords.length - 1]
            let dx = p2[0] - p1[0]
            let dy = p2[1] - p1[1]
            let segLen = getDistMeters({ x: p1[0], y: p1[1] }, { x: p2[0], y: p2[1] })
            if (segLen > 0) {
                let mPerDegLat = 111320
                let mPerDegLon = Math.cos(p2[1] * Math.PI / 180) * 111320
                let extLon = p2[0] + (dx / segLen) * (10 / mPerDegLon)
                let extLat = p2[1] + (dy / segLen) * (10 / mPerDegLat)
                extCoords = coords.concat([[extLon, extLat]])
            }
        }
        drawLineFromCoords(extCoords, carRenderer)
        lastRouteCoords = coords
        refinePolygonTargetsFromRoute(coords, snap)
        if (distOffRoad > 20 && !(currentTarget && currentTarget.onRoute)) {
            routeHasFootSegment = true
            drawDirectLine(snap, currentTarget, footRenderer)
            if (getDistMeters(start, snap) < 30) {
                parkedLocation = snap
                navState = "WALKING_TO_POI"
                lastFootPos = null
                lastFootRouteCoords = null
                footRoutePending = false
                updatePolygonCenterRenderer()
                updateArrowRenderer()
                showHudMessage(tr("Fin de route.\nFinir à pied."), true)
            }
        } else {
            routeHasFootSegment = false
            clearGeometry(footRenderer)
        }
        mapCanvas.refresh()
    } 

    function refinePolygonTargetsFromRoute(routeCoords, snap) {
        if (!routeCoords || routeCoords.length < 2) return
        let hasParking = parkedLocation && parkedLocation.x

        let refCoords = routeCoords
        let cumDist = 0
        for (let i = routeCoords.length - 2; i >= 1; i--) {
            cumDist += getDistMeters(
                { x: routeCoords[i][0],   y: routeCoords[i][1] },
                { x: routeCoords[i+1][0], y: routeCoords[i+1][1] }
            )
            if (cumDist > 120) { refCoords = routeCoords.slice(0, i + 1); break }
        }
        if (refCoords.length < 2) refCoords = routeCoords.slice(0, routeCoords.length - 1)
        if (refCoords.length < 2) return

        let updated = unvisitedPoints.map(function(pt) {
            let verts = polygonVertices[pt.id]
            if (!verts || verts.length === 0) return pt

            let bestPt = null
            let bestDist = 1e9

            if (hasParking) {
                for (let j = 0; j < verts.length; j++) {
                    let dParking = getDistMeters(parkedLocation, verts[j])
                    let dRoute = minDistToRouteLine(verts[j], refCoords)
                    let d = dParking + dRoute
                    if (d < bestDist) { bestDist = d; bestPt = verts[j] }
                }
            } else {
                for (let j = 0; j < verts.length; j++) {
                    let d = minDistToRouteLine(verts[j], refCoords)
                    if (d < bestDist) { bestDist = d; bestPt = verts[j] }
                }
                if (bestDist > 250) return pt
            }

            if (!bestPt) return pt

            let isOnRoute = minDistToRouteLine(bestPt, refCoords) < 20
            return { id: pt.id, x: bestPt.x, y: bestPt.y, onRoute: isOnRoute, isolated: pt.isolated }
        })

        unvisitedPoints = updated
        if (currentTarget) {
            let refreshed = unvisitedPoints.find(function(p) { return p.id === currentTarget.id })
            if (refreshed) currentTarget = refreshed
        }
        updateOnRouteRenderer()
        updatePolygonCenterRenderer()
        updateArrowRenderer()
        mapCanvas.refresh()
    }

    function chainIsolatedPoints(rawPoints) {
        let isolated = rawPoints.filter(function(p) { return p.isolated })
        if (isolated.length === 0) return
        let accessible = rawPoints.filter(function(p) { return !p.isolated })
        if (accessible.length === 0) return

        for (let i = 0; i < isolated.length; i++) {
            let iso = isolated[i]
            let isoVerts = polygonVertices[iso.id]
            if (!isoVerts || isoVerts.length === 0) continue

            let bestNeighborVert = null
            let bestPairDist = 1e9
            let bestIsoVert = null

            for (let j = 0; j < accessible.length; j++) {
                let acc = accessible[j]
                let accVerts = polygonVertices[acc.id]
                let accPts = (accVerts && accVerts.length > 0) ? accVerts : [{ x: acc.x, y: acc.y }]
                for (let v = 0; v < accPts.length; v++) {
                    for (let w = 0; w < isoVerts.length; w++) {
                        let d = getDistMeters(accPts[v], isoVerts[w])
                        if (d < bestPairDist) {
                            bestPairDist = d
                            bestNeighborVert = accPts[v]
                            bestIsoVert = isoVerts[w]
                        }
                    }
                }
            }
            if (!bestIsoVert) continue

            let idx = rawPoints.indexOf(iso)
            if (idx >= 0) {
                rawPoints[idx] = {
                    id: iso.id,
                    x: bestIsoVert.x,
                    y: bestIsoVert.y,
                    onRoute: false,
                    isolated: true,
                    chained: true
                }
            }
        }
    }

    function shouldParkHere(myPos, remainingPts) {
        if (!remainingPts || remainingPts.length === 0) return false

        // Se garer uniquement si des points isolés sont dans le rayon de marche
        // ET qu'aucun n'est accessible en voiture dans ce même rayon
        let inRadius = getPointsInWalkRadius(myPos, remainingPts)
        if (inRadius.length === 0) return false

        let hasCarAccess = inRadius.find(function(p) { return !p.isolated })
        if (hasCarAccess) return false

        return true
    }

    // --- Rendu fuschia ---
    function updatePolygonCenterRenderer() {
        // Si une cible vient d'être validée, couper brièvement le renderer
        // pour forcer le redémarrage de l'animation sur la nouvelle géométrie
        if (targetJustValidated) {
            let empty = GeometryUtils.createGeometryFromWkt("LINESTRING(0 0, 0.000001 0.000001)")
            if (empty) polygonCenterRenderer.geometryWrapper.qgsGeometry = empty
            targetJustValidated = false
            // Relancer après un bref délai pour que l'animation reparte du début
            resetPolygonTimer.restart()
            return
        }
        let empty = GeometryUtils.createGeometryFromWkt("LINESTRING(0 0, 0.000001 0.000001)")
        let candidates = unvisitedPoints.filter(function(p) { return p.onRoute })
        if (navState === "WALKING_TO_POI" && currentTarget &&
            !candidates.find(function(p) { return p.id === currentTarget.id })) {
            candidates = candidates.concat([currentTarget])
        }
        if (candidates.length === 0) {
            if (empty) polygonCenterRenderer.geometryWrapper.qgsGeometry = empty
            return
        }
        let polygons = []
        for (let i = 0; i < candidates.length; i++) {
            let verts = polygonVertices[candidates[i].id]
            if (!verts || verts.length < 3) continue
            let ring = verts.map(function(v) { return v.x.toFixed(6) + " " + v.y.toFixed(6) })
            let first = verts[0], last = verts[verts.length - 1]
            if (first.x !== last.x || first.y !== last.y) {
                ring.push(first.x.toFixed(6) + " " + first.y.toFixed(6))
            }
            polygons.push("((" + ring.join(",") + "))")
        }
        if (polygons.length === 0) {
            if (empty) polygonCenterRenderer.geometryWrapper.qgsGeometry = empty
            return
        }
        let wkt = polygons.length === 1
            ? "POLYGON" + polygons[0]
            : "MULTIPOLYGON(" + polygons.join(",") + ")"
        let geom = GeometryUtils.createGeometryFromWkt(wkt)
        if (geom) polygonCenterRenderer.geometryWrapper.qgsGeometry = geom
    }

    function updateArrowRenderer() {
        let empty = GeometryUtils.createGeometryFromWkt("LINESTRING(0 0, 0.000001 0.000001)")
        if (empty) arrowRenderer.geometryWrapper.qgsGeometry = empty
    }

    // --- 10. DESSIN ---
    function drawDirectLine(start, end, renderer) {
        let wkt = "LINESTRING(" + start.x.toFixed(6) + " " + start.y.toFixed(6) + ", " + end.x.toFixed(6) + " " + end.y.toFixed(6) + ")"
        let geom = GeometryUtils.createGeometryFromWkt(wkt)
        if(geom) renderer.geometryWrapper.qgsGeometry = geom
    }

    function drawLineFromCoords(coords, renderer) {
        if (!coords || coords.length < 2) return
        let pts = []
        for (let i = 0; i < coords.length; i++) pts.push(coords[i][0] + " " + coords[i][1])
        let wkt = "LINESTRING(" + pts.join(",") + ")"
        let geom = GeometryUtils.createGeometryFromWkt(wkt)
        if(geom) renderer.geometryWrapper.qgsGeometry = geom
    }

    function clearGeometry(renderer) {
        let empty = GeometryUtils.createGeometryFromWkt("LINESTRING(0 0, 0.000001 0.000001)") 
        if(empty) renderer.geometryWrapper.qgsGeometry = empty
    }

    function trimRouteToCurrentPos(pos) {
        if (!lastRouteCoords || lastRouteCoords.length < 2) return false
        let minDist = 1e9
        let closestIdx = 0
        for (let i = 0; i < lastRouteCoords.length; i++) {
            let pt = { x: lastRouteCoords[i][0], y: lastRouteCoords[i][1] }
            let d = getDistMeters(pos, pt)
            if (d < minDist) { minDist = d; closestIdx = i }
        }

        if (routeHasFootSegment) {
            let remainingDist = 0
            for (let j = closestIdx; j < lastRouteCoords.length - 1; j++) {
                remainingDist += getDistMeters(
                    { x: lastRouteCoords[j][0],   y: lastRouteCoords[j][1] },
                    { x: lastRouteCoords[j+1][0], y: lastRouteCoords[j+1][1] }
                )
            }
            if (remainingDist < 10 && navState === "DRIVING") {
                parkedLocation = { x: pos.x, y: pos.y }
                currentTarget = pickBestVertex(currentTarget)
                navState = "WALKING_TO_POI"
                routeHasFootSegment = false
                lastFootRouteCoords = null
                footRoutePending = false
                lastFootPos = null
                updatePolygonCenterRenderer()
                updateArrowRenderer()
                showHudMessage(tr("Voiture stationnée.\nFinir à pied."), true)
                return true
            }
        }

        if (closestIdx === 0) return false
        let remaining = lastRouteCoords.slice(closestIdx)
        lastRouteCoords = remaining
        if (remaining.length >= 2) {
            drawLineFromCoords(remaining, carRenderer)
        }
        return true
    }

    // --- 11. UTILS ---
    function getCurrentGpsPosition() {
        // Tentative 1 : iface.positionSource
        if (iface.positionSource && iface.positionSource.active) {
            let gpsPt = iface.positionSource.sourcePosition
            if (gpsPt && (gpsPt.x !== 0 || gpsPt.y !== 0)) {
                return { x: gpsPt.x, y: gpsPt.y }
            }
        }
        // Tentative 2 : locator.positionInformation
        try {
            let locatorItem = iface.findItemByObjectName("locator")
            if (locatorItem && locatorItem.positionInformation) {
                let pi = locatorItem.positionInformation
                if (pi.latitude !== undefined && pi.longitude !== undefined
                        && (pi.latitude !== 0 || pi.longitude !== 0)) {
                    return { x: pi.longitude, y: pi.latitude }
                }
            }
        } catch(e) {}
        // Tentative 3 : navigation.location (QgsPoint C++ en CRS carte → reprojeter en WGS84)
        try {
            let navItem = iface.findItemByObjectName("navigation")
            if (navItem && navItem.location) {
                let loc = navItem.location
                if ((loc.x !== 0 || loc.y !== 0)) {
                    let wgs = GeometryUtils.reprojectPointToWgs84(loc, mapCanvas.mapSettings.destinationCrs)
                    if (wgs && (wgs.x !== 0 || wgs.y !== 0)) {
                        return { x: wgs.x, y: wgs.y }
                    }
                }
            }
        } catch(e) {}
        
        return null
    }

    function getMapCenter() {
        let extent = mapCanvas.mapSettings.extent
        let cx = (extent.xMinimum + extent.xMaximum) / 2
        let cy = (extent.yMinimum + extent.yMaximum) / 2
        let wkt = "POINT(" + cx + " " + cy + ")"
        let g = GeometryUtils.createGeometryFromWkt(wkt)
        if (g) {
            let p = GeometryUtils.centroid(g)
            let w = GeometryUtils.reprojectPointToWgs84(p, mapCanvas.mapSettings.destinationCrs)
            if (w) return { x: w.x, y: w.y }
        }
        return null
    }

    function getCrosshairPosition() {
        try {
            let locatorItem = iface.findItemByObjectName("locator")
            if (locatorItem && locatorItem.currentCoordinate) {
                let coord = locatorItem.currentCoordinate
                let wgs = GeometryUtils.reprojectPointToWgs84(coord, mapCanvas.mapSettings.destinationCrs)
                if (wgs && (wgs.x !== 0 || wgs.y !== 0)) return { x: wgs.x, y: wgs.y }
            }
        } catch(e) {}
        return getMapCenter()
    }

    function getDistMeters(pt1, pt2) {
        if (!pt1 || !pt2) return 100000;
        var R = 6371000; 
        var dLat = (pt2.y - pt1.y) * (Math.PI/180);
        var dLon = (pt2.x - pt1.x) * (Math.PI/180); 
        var a = Math.sin(dLat/2) * Math.sin(dLat/2) + Math.cos(pt1.y * (Math.PI/180)) * Math.cos(pt2.y * (Math.PI/180)) * Math.sin(dLon/2) * Math.sin(dLon/2); 
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a)); 
        return R * c; 
    }
}
