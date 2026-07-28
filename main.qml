import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Theme
import org.qfield
import org.qgis
import "qrc:/qml" as QFieldItems
import QtCore
import "."

Item {
    id: filterToolRoot

    // === PROPRIÉTÉS QFIELD ===
    property var mainWindow: iface.mainWindow()
    property var mapCanvas: iface.mapCanvas()
    property var featureFormItem: iface.findItemByObjectName("featureForm")
    property var dashBoard: iface.findItemByObjectName('dashBoard')
    property var overlayFeatureFormDrawer: iface.findItemByObjectName('overlayFeatureFormDrawer')

    // Variables de sélection (Filtre 1)
    property var selectedLayer: null
    // Variables de sélection (Filtre 2)
    property var selectedLayer2: null

    // Suivi de la visibilité des couches (légende) pour lier les switches de filtre
    // à l'affichage réel des couches — sens unique : visibilité couche → état switch
    property var layerVisibilitySnapshot: ({})

    // Détection type source
    property bool sourceIsPoints: false
    property bool sourceIsPoints2: false

    // État du filtre
    property bool filterActive: false
    property bool filterActive2: false
    property bool isFormVisible: false

    // Persistance - Filtre 1
    property bool showAllFeatures: false
    property bool showFeatureList: false
    property bool filter1Enabled: true 
    // Coloriage indépendant : garde le filtrage (subsetString) mais masque les
    // contours/points colorés au profit de la symbologie native de la couche
    property bool colorize1Enabled: true
    property string savedLayerName: ""
    property string savedFieldName: ""
    property string savedFilterText: ""
    property string savedExpr: ""

    // Persistance - Filtre 2
    property bool showAllFeatures2: false
    property bool showFeatureList2: false
    property bool filter2Enabled: true 
    property bool colorize2Enabled: true
    property string savedLayerName2: ""
    property string savedFieldName2: ""
    property string savedFilterText2: ""
    property string savedExpr2: ""

    // Navigation
    property bool useListOffset: false
    property bool isReturnAction: false
    property bool wasLongPress: false

    // Couleurs
    property color targetFocusColor: "#D500F9"
    property color targetSelectedColor: "#23FF0A"
    property color origFocusColor: "#ff7777"
    property color origSelectedColor: Theme.mainColor
    property color origBaseColor: "yellow"
    property color origProjectColor: "yellow"
    property var highlightItem: null

    // Palette — une couleur par valeur de filtre
    property var colorPalette: [
        "#FF4444",   // valeur 1 — rouge
        "#4488FF",   // valeur 2 — bleu
        "#00FF39",   // valeur 3 — vert fluo
        "#AA00FF",   // valeur 4 — violet
        "#40767F",   // valeur 5 — cyan fonce
        "#FF44AA"    // valeur 6 — rose
    ]
    
    // Palette — Filtre 2 (ex: tons oranges/jaunes/marrons pour différencier)
    property var colorPalette2: [
        "#FF8800",   // orange
        "#FFCC00",   // jaune
        "#884400",   // marron
        "#FF0088",   // fushia
        "#00FFEE",   //turquoise
        "#888888"    // gris
    ]
    property int maxFilterValues: 6

    //Zoom ON/OFF
    property bool doAutoZoom: true
    property bool doAutoZoom2: true

    // Géométries et centroïdes Filtre 1
    property var centroidPoints: []
    property var outlinePolygons: []
    property var clusteredPoints: []
    property real clusterRadius: 47

    // Géométries et centroïdes Filtre 2
    property var centroidPoints2: []
    property var outlinePolygons2: []
    property var clusteredPoints2: []

    // Variables internes
    property var pendingFormLayer: null
    property string pendingFormExpr: ""
    property var internalListView: null
    property bool wasListVisible: true
    property var pendingDriveMeLayer: null

    Settings {
        id: pluginSettings
        category: "QFieldFilterPlugin"
        
        // Réglages Filtre 1
        property alias savedLayerName: filterToolRoot.savedLayerName
        property alias savedFieldName: filterToolRoot.savedFieldName
        property alias savedFilterText: filterToolRoot.savedFilterText
        property alias showAllFeatures: filterToolRoot.showAllFeatures
        property alias showFeatureList: filterToolRoot.showFeatureList
        property alias filter1Enabled: filterToolRoot.filter1Enabled 
        property alias colorize1Enabled: filterToolRoot.colorize1Enabled
        property alias doAutoZoom: filterToolRoot.doAutoZoom
        property alias filterActive: filterToolRoot.filterActive

        // Réglages Filtre 2
        property alias savedLayerName2: filterToolRoot.savedLayerName2
        property alias savedFieldName2: filterToolRoot.savedFieldName2
        property alias savedFilterText2: filterToolRoot.savedFilterText2
        property alias showAllFeatures2: filterToolRoot.showAllFeatures2
        property alias showFeatureList2: filterToolRoot.showFeatureList2
        property alias filter2Enabled: filterToolRoot.filter2Enabled 
        property alias colorize2Enabled: filterToolRoot.colorize2Enabled
        property alias doAutoZoom2: filterToolRoot.doAutoZoom2
        property alias filterActive2: filterToolRoot.filterActive2
    }

    //==============================================
    // 1. INSTANCIATION DES PLUGINS ENFANTS
    // -------------------------------------------
    DriveMe {
        id: drivemeTool
    }

    // === INITIALISATION ===
    Component.onCompleted: {
        iface.addItemToPluginsToolbar(toolbarButton)
        updateLayers()
        if (featureFormItem) isFormVisible = featureFormItem.visible
        var container = iface.findItemByObjectName("mapCanvasContainer")
        if (container) findHighlighterRecursive(container)
        if (qgisProject) origProjectColor = qgisProject.selectionColor
        applyCustomColors()

        // Restauration Filtre 1
        if (filterActive && savedLayerName && savedFieldName && savedFilterText) {
            restoreTimer.start()
        }
        // Restauration Filtre 2
        if (filterActive2 && savedLayerName2 && savedFieldName2 && savedFilterText2) {
            restoreTimer2.start()
        }

        layerVisibilitySnapshot = snapshotLayerVisibility()
    }

    // === SUIVI VISIBILITÉ DES COUCHES (légende) → SWITCHES DE FILTRE ===
    // Sens unique voulu : quand une couche est (dés)affichée dans la légende,
    // le switch du filtre correspondant suit automatiquement. L'inverse n'est
    // jamais fait ici — activer/désactiver un switch ne touche jamais la légende.
    function snapshotLayerVisibility() {
        let snap = ({})
        if (!flatLayerTree) return snap
        let count = flatLayerTree.rowCount()
        for (let i = 0; i < count; i++) {
            let idx = flatLayerTree.index(i, 0)
            if (flatLayerTree.data(idx, FlatLayerTreeModel.Type) === FlatLayerTreeModel.Layer) {
                let name = flatLayerTree.data(idx, FlatLayerTreeModel.Name)
                snap[name] = flatLayerTree.data(idx, FlatLayerTreeModel.Visible)
            }
        }
        return snap
    }

    Connections {
        target: flatLayerTree
        ignoreUnknownSignals: true
        function onDataChanged() {
            let newSnap = filterToolRoot.snapshotLayerVisibility()
            for (let name in newSnap) {
                let wasVisible = filterToolRoot.layerVisibilitySnapshot[name]
                let isVisible = newSnap[name]
                if (wasVisible === isVisible) continue

                // Filtre 1 : ne suit que si ce nom correspond à la couche sélectionnée pour ce filtre
                if (filterToolRoot.selectedLayer && filterToolRoot.selectedLayer.name === name) {
                    filterToolRoot.filter1Enabled = isVisible
                }
                // Filtre 2 : idem, indépendamment
                if (filterToolRoot.selectedLayer2 && filterToolRoot.selectedLayer2.name === name) {
                    filterToolRoot.filter2Enabled = isVisible
                }
            }
            filterToolRoot.layerVisibilitySnapshot = newSnap
        }
    }

    //======= TIMERS DE RESTAURATION =========
    Timer {
        id: restoreTimer
        property int attempts: 0
        interval: 1000
        repeat: true
        onTriggered: {
            attempts++
            var layer = getLayerByName(savedLayerName)
            if (layer) {
                stop()
                selectedLayer = layer
                checkSourceGeometryType()
                updateFields()
                var fields = getFields(selectedLayer)
                var idx = fields.indexOf(savedFieldName)
                if (idx >= 0) fieldSelector.currentIndex = idx
                valueField.text = savedFilterText
                updateApplyState()
                
                // 1. Application du filtre (uniquement si activé par le switch)
                if (filter1Enabled) {
                    applyFilter(false, doAutoZoom)
                }
                
                // 2. AJOUT : Si c'est une couche de points, on supprime la sélection jaune
                if (sourceIsPoints && selectedLayer) {
                    selectedLayer.removeSelection()
                    selectedLayer.triggerRepaint()
                    mapCanvas.refresh()
                }
            } else if (attempts >= 45) {
                stop()
            }
        }
    }

    Timer {
        id: restoreTimer2
        property int attempts: 0
        interval: 1000
        repeat: true
        onTriggered: {
            attempts++
            var layer = getLayerByName(savedLayerName2)
            if (layer) {
                stop()
                selectedLayer2 = layer
                checkSourceGeometryType2()
                updateFields2()
                var fields = getFields(selectedLayer2)
                var idx = fields.indexOf(savedFieldName2)
                if (idx >= 0) fieldSelector2.currentIndex = idx
                valueField2.text = savedFilterText2
                updateApplyState2()
                
                // 1. Application du filtre (uniquement si activé par le switch 2)
                if (filter2Enabled) {
                    applyFilter2(false, doAutoZoom2)
                }
                
                // 2. AJOUT : Si c'est une couche de points, on supprime la sélection jaune
                if (sourceIsPoints2 && selectedLayer2) {
                    selectedLayer2.removeSelection()
                    selectedLayer2.triggerRepaint()
                    mapCanvas.refresh()
                }
            } else if (attempts >= 45) {
                stop()
            }
        }
    }

    // === BOUTON TOOLBAR ===
    QfToolButton {
        id: toolbarButton
        iconSource: "icon.svg"
        iconColor: Theme.mainColor
        bgcolor: Theme.darkGray
        round: true

        onClicked: {
            if (!filterToolRoot.wasLongPress) {
                openFilterUI()
            }
            filterToolRoot.wasLongPress = false
        }

        onPressed: holdTimer.start()
        onReleased: holdTimer.stop()

        Timer {
            id: holdTimer
            interval: 500
            repeat: false
            onTriggered: {
                filterToolRoot.wasLongPress = true
                if (filterToolRoot.targetPointLayer) {
                    filterToolRoot.clearTargetLayer(true)
                }
                
                // Supprime le Filtre 1 en mode silencieux, puis le Filtre 2
                removeAllFilters(true)
                removeAllFilters2()

                // Affiche la notification globale
                mainWindow.displayToast(tr("Filters 1 and 2 deleted"))
            }
        }
    }   

    // === LOGIQUE TYPE GÉOMÉTRIE ===
    function checkSourceGeometryType() {
        if (!selectedLayer) { sourceIsPoints = false; return }
        var gType = -1
        try {
            if (typeof selectedLayer.geometryType === 'number') gType = selectedLayer.geometryType
            else if (typeof selectedLayer.geometryType === 'function') gType = selectedLayer.geometryType()
        } catch (e) {}
        sourceIsPoints = (gType === 0)
    }

    function checkSourceGeometryType2() {
        if (!selectedLayer2) { sourceIsPoints2 = false; return }
        var gType = -1
        try {
            if (typeof selectedLayer2.geometryType === 'number') gType = selectedLayer2.geometryType
            else if (typeof selectedLayer2.geometryType === 'function') gType = selectedLayer2.geometryType()
        } catch (e) {}
        sourceIsPoints2 = (gType === 0)
    }

    // === CALCUL CENTROÏDES + CONTOURS (Filtre 1) ===
    function computeCentroids() {
        if (sourceIsPoints) { clearCentroids(); return }
        if (!selectedLayer || !savedFieldName || !savedFilterText) return

        var fieldName = savedFieldName
        var values = savedFilterText.split(";").map(function(v) { return escapeValue(v.toLowerCase().trim()) }).filter(function(v) { return v.length > 0 })

        var newCentroidPoints = []
        var newOutlinePolygons = []

        for (var vi = 0; vi < maxFilterValues; vi++) {
            if (vi >= values.length) continue
            var singleExpr = 'lower("' + fieldName + '") LIKE \'%' + values[vi] + '%\''
            var entries = []
            try {
                var it = LayerUtils.createFeatureIteratorFromExpression(selectedLayer, singleExpr)
                while (it.hasNext()) {
                    var feat = it.next()
                    var geom = feat.geometry
                    if (!geom) continue
                    var centPt = pointInsideGeom(geom)
                    if (centPt) {
                        var wgs = GeometryUtils.reprojectPointToWgs84(centPt, selectedLayer.crs)
                        if (wgs) newCentroidPoints.push({ x: wgs.x, y: wgs.y, colorIdx: vi })
                    }
                    var verts = extractWgs84Vertices(geom, selectedLayer.crs)
                    if (verts && verts.length >= 3) entries.push({ verts: verts })
                }
            } catch(e) {}
            buildOutlineEntriesForGroup(entries, vi, newOutlinePolygons)
        }
        centroidPoints = newCentroidPoints
        outlinePolygons = newOutlinePolygons
        buildClusters()
        if (mapCanvas) mapCanvas.refresh()
    }

    function clearCentroids() {
        centroidPoints = []
        clusteredPoints = []
        outlinePolygons = []
    }

    // === CALCUL CENTROÏDES + CONTOURS (Filtre 2) ===
    function computeCentroids2() {
        if (sourceIsPoints2) { clearCentroids2(); return }
        if (!selectedLayer2 || !savedFieldName2 || !savedFilterText2) return

        var fieldName = savedFieldName2
        var values = savedFilterText2.split(";").map(function(v) { return escapeValue(v.toLowerCase().trim()) }).filter(function(v) { return v.length > 0 })

        var newCentroidPoints = []
        var newOutlinePolygons = []

        for (var vi = 0; vi < maxFilterValues; vi++) {
            if (vi >= values.length) continue
            var singleExpr = 'lower("' + fieldName + '") LIKE \'%' + values[vi] + '%\''
            var entries = []
            try {
                var it = LayerUtils.createFeatureIteratorFromExpression(selectedLayer2, singleExpr)
                while (it.hasNext()) {
                    var feat = it.next()
                    var geom = feat.geometry
                    if (!geom) continue
                    var centPt = pointInsideGeom(geom)
                    if (centPt) {
                        var wgs = GeometryUtils.reprojectPointToWgs84(centPt, selectedLayer2.crs)
                        if (wgs) newCentroidPoints.push({ x: wgs.x, y: wgs.y, colorIdx: vi })
                    }
                    var verts = extractWgs84Vertices(geom, selectedLayer2.crs)
                    if (verts && verts.length >= 3) entries.push({ verts: verts })
                }
            } catch(e) {}
            buildOutlineEntriesForGroup(entries, vi, newOutlinePolygons)
        }
        centroidPoints2 = newCentroidPoints
        outlinePolygons2 = newOutlinePolygons
        buildClusters2()
        if (mapCanvas) mapCanvas.refresh()
    }

    function clearCentroids2() {
        centroidPoints2 = []
        clusteredPoints2 = []
        outlinePolygons2 = []
    }

    function buildClusters() {
        if (!centroidPoints || centroidPoints.length === 0) { clusteredPoints = []; return }
        var ext = mapCanvas.mapSettings.extent
        var destCrs = mapCanvas.mapSettings.destinationCrs
        var wgs84Ext = null
        try {
            wgs84Ext = GeometryUtils.reprojectRectangle(ext, destCrs, CoordinateReferenceSystemUtils.wgs84Crs())
        } catch(e) {}

        if (!wgs84Ext || mapCanvas.width === 0 || mapCanvas.height === 0) {
            clusteredPoints = centroidPoints.slice(); return
        }

        var threshX = clusterRadius * (wgs84Ext.xMaximum - wgs84Ext.xMinimum) / mapCanvas.width
        var threshY = clusterRadius * (wgs84Ext.yMaximum - wgs84Ext.yMinimum) / mapCanvas.height

        var assigned = new Array(centroidPoints.length).fill(false)
        var result = []
        for (var i = 0; i < centroidPoints.length; i++) {
            if (assigned[i]) continue
            var p = centroidPoints[i]
            var sumX = p.x; var sumY = p.y; var clusterCount = 1
            assigned[i] = true

            for (var j = i + 1; j < centroidPoints.length; j++) {
                if (assigned[j]) continue
                var q = centroidPoints[j]
                if (q.colorIdx === p.colorIdx && Math.abs(p.x - q.x) < threshX && Math.abs(p.y - q.y) < threshY) {
                    sumX += q.x; sumY += q.y; clusterCount++
                    assigned[j] = true
                }
            }
            result.push({ x: sumX / clusterCount, y: sumY / clusterCount, colorIdx: p.colorIdx, clusterCount: clusterCount })
        }
        clusteredPoints = result
    }

    function buildClusters2() {
        if (!centroidPoints2 || centroidPoints2.length === 0) { clusteredPoints2 = []; return }
        var ext = mapCanvas.mapSettings.extent
        var destCrs = mapCanvas.mapSettings.destinationCrs
        var wgs84Ext = null
        try {
            wgs84Ext = GeometryUtils.reprojectRectangle(ext, destCrs, CoordinateReferenceSystemUtils.wgs84Crs())
        } catch(e) {}

        if (!wgs84Ext || mapCanvas.width === 0 || mapCanvas.height === 0) {
            clusteredPoints2 = centroidPoints2.slice(); return
        }

        var threshX = clusterRadius * (wgs84Ext.xMaximum - wgs84Ext.xMinimum) / mapCanvas.width
        var threshY = clusterRadius * (wgs84Ext.yMaximum - wgs84Ext.yMinimum) / mapCanvas.height

        var assigned = new Array(centroidPoints2.length).fill(false)
        var result = []
        for (var i = 0; i < centroidPoints2.length; i++) {
            if (assigned[i]) continue
            var p = centroidPoints2[i]
            var sumX = p.x; var sumY = p.y; var clusterCount = 1
            assigned[i] = true

            for (var j = i + 1; j < centroidPoints2.length; j++) {
                if (assigned[j]) continue
                var q = centroidPoints2[j]
                if (q.colorIdx === p.colorIdx && Math.abs(p.x - q.x) < threshX && Math.abs(p.y - q.y) < threshY) {
                    sumX += q.x; sumY += q.y; clusterCount++
                    assigned[j] = true
                }
            }
            result.push({ x: sumX / clusterCount, y: sumY / clusterCount, colorIdx: p.colorIdx, clusterCount: clusterCount })
        }
        clusteredPoints2 = result
    }

    // === POINT GARANTI DANS LA GÉOMÉTRIE ===
    function _pointInPolygon(px, py, coords) {
        var inside = false
        var n = coords.length
        for (var i = 0, j = n - 1; i < n; j = i++) {
            var xi = coords[i][0], yi = coords[i][1]
            var xj = coords[j][0], yj = coords[j][1]
            if (((yi > py) !== (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi) + xi))
                inside = !inside
        }
        return inside
    }

    function _extractRawCoords(geom) {
        var coords = []
        try {
            var wkt = geom.asWkt()
            if (!wkt) return coords
            var start = wkt.indexOf("((")
            if (start === -1) start = wkt.indexOf("(")
            if (start === -1) return coords
            start = wkt.indexOf("(", start) + 1
            var end = wkt.indexOf(")", start)
            if (end === -1) return coords
            var pairs = wkt.substring(start, end).split(",")
            for (var i = 0; i < pairs.length; i++) {
                var xy = pairs[i].trim().split(" ")
                if (xy.length < 2) continue
                var x = parseFloat(xy[0]), y = parseFloat(xy[1])
                if (!isNaN(x) && !isNaN(y)) coords.push([x, y])
            }
        } catch(e) {}
        return coords
    }

    function pointInsideGeom(geom) {
        try {
            var coords = _extractRawCoords(geom)
            if (coords.length < 3) return GeometryUtils.centroid(geom)
            var sumX = 0, sumY = 0
            for (var k = 0; k < coords.length; k++) { sumX += coords[k][0]; sumY += coords[k][1] }
            var cx = sumX / coords.length
            var cy = sumY / coords.length
            if (_pointInPolygon(cx, cy, coords)) {
                var ptGeom = GeometryUtils.createGeometryFromWkt("POINT(" + cx + " " + cy + ")")
                if (ptGeom) return GeometryUtils.centroid(ptGeom)
            }
            var n = coords.length
            for (var i = 0; i < n - 1; i++) {
                var mx = (coords[i][0] + coords[i+1][0]) / 2
                var my = (coords[i][1] + coords[i+1][1]) / 2
                if (_pointInPolygon(mx, my, coords)) {
                    var px2 = mx + (cx - mx) * 0.40
                    var py2 = my + (cy - my) * 0.40
                    var mGeom = GeometryUtils.createGeometryFromWkt("POINT(" + px2 + " " + py2 + ")")
                    if (mGeom) return GeometryUtils.centroid(mGeom)
                }
            }
        } catch(e) {}
        return GeometryUtils.centroid(geom)
    }

    function extractWgs84Vertices(geom, layerCrs) {
        var verts = []
        try {
            var wkt = geom.asWkt()
            if (!wkt) return verts
            var start = wkt.indexOf("((")
            if (start === -1) start = wkt.indexOf("(")
            if (start === -1) return verts
            start = wkt.indexOf("(", start) + 1
            var end = wkt.indexOf(")", start)
            if (end === -1) return verts
            var pairs = wkt.substring(start, end).split(",")
            for (var i = 0; i < pairs.length; i++) {
                var xy = pairs[i].trim().split(" ")
                if (xy.length < 2) continue
                var x = parseFloat(xy[0]), y = parseFloat(xy[1])
                if (isNaN(x) || isNaN(y)) continue
                var vWkt = "POINT(" + x + " " + y + ")"
                var vGeom = GeometryUtils.createGeometryFromWkt(vWkt)
                if (!vGeom) continue
                var vPt = GeometryUtils.centroid(vGeom)
                if (!vPt) continue
                var wgs = GeometryUtils.reprojectPointToWgs84(vPt, layerCrs)
                if (wgs) verts.push({ x: wgs.x, y: wgs.y })
            }
        } catch(e) {}
        return verts
    }

    function ringBBox(verts) {
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
        for (var i = 0; i < verts.length; i++) {
            var v = verts[i]
            if (v.x < minX) minX = v.x; if (v.x > maxX) maxX = v.x
            if (v.y < minY) minY = v.y; if (v.y > maxY) maxY = v.y
        }
        return { minX: minX, minY: minY, maxX: maxX, maxY: maxY }
    }

    function bboxOverlap(a, b, eps) {
        eps = eps || 1e-6
        return a.minX <= b.maxX + eps && a.maxX >= b.minX - eps && a.minY <= b.maxY + eps && a.maxY >= b.minY - eps
    }

    function ringsShareVertex(vertsA, vertsB, eps) {
        eps = eps || 1e-6
        for (var i = 0; i < vertsA.length; i++) {
            for (var j = 0; j < vertsB.length; j++) {
                if (Math.abs(vertsA[i].x - vertsB[j].x) < eps && Math.abs(vertsA[i].y - vertsB[j].y) < eps) return true
            }
        }
        return false
    }

    function groupRingsForMerge(entries) {
        var n = entries.length
        var bboxes = entries.map(function(e) { return ringBBox(e.verts) })
        var hasConflict = new Array(n).fill(false)
        for (var i = 0; i < n; i++) {
            for (var j = i + 1; j < n; j++) {
                if (!bboxOverlap(bboxes[i], bboxes[j])) continue
                if (ringsShareVertex(entries[i].verts, entries[j].verts)) {
                    hasConflict[i] = true; hasConflict[j] = true
                }
            }
        }
        var isolated = [], mergeable = []
        for (var i = 0; i < n; i++) {
            if (hasConflict[i]) isolated.push(i)
            else mergeable.push(i)
        }
        return { isolated: isolated, mergeable: mergeable }
    }

    function buildOutlineEntriesForGroup(entries, colorIdx, targetArray) {
        if (entries.length === 0) return
        var grouped = groupRingsForMerge(entries)
        if (grouped.mergeable.length === 1) {
            grouped.isolated.push(grouped.mergeable[0])
            grouped.mergeable = []
        }
        if (grouped.mergeable.length > 1) {
            var polygons = grouped.mergeable.map(function(idx) {
                var verts = entries[idx].verts
                var ring = verts.map(function(v) { return v.x.toFixed(6) + " " + v.y.toFixed(6) })
                var first = verts[0], last = verts[verts.length - 1]
                if (first.x !== last.x || first.y !== last.y) ring.push(first.x.toFixed(6) + " " + first.y.toFixed(6))
                return "((" + ring.join(",") + "))"
            })
            var wkt = "MULTIPOLYGON(" + polygons.join(",") + ")"
            var geom = GeometryUtils.createGeometryFromWkt(wkt)
            if (geom) targetArray.push({ colorIdx: colorIdx, geom: geom })
        }
        for (var k = 0; k < grouped.isolated.length; k++) {
            var verts = entries[grouped.isolated[k]].verts
            var geom2 = buildPolygonGeometry(verts)
            if (geom2) targetArray.push({ colorIdx: colorIdx, geom: geom2 })
        }
    }

    function buildPolygonGeometry(verts) {
        if (!verts || verts.length < 3) return null
        var ring = verts.map(function(v) { return v.x.toFixed(6) + " " + v.y.toFixed(6) })
        var first = verts[0], last = verts[verts.length - 1]
        if (first.x !== last.x || first.y !== last.y) ring.push(first.x.toFixed(6) + " " + first.y.toFixed(6))
        var wkt = "POLYGON((" + ring.join(",") + "))"
        return GeometryUtils.createGeometryFromWkt(wkt)
    }

    // === UTILITAIRES COULEURS / FORMES ===
    function findListViewRecursive(parentItem) {
        if (!parentItem) return null
        if (parentItem.hasOwnProperty("delegate") && parentItem.hasOwnProperty("model") && parentItem.hasOwnProperty("currentIndex")) return parentItem
        var kids = parentItem.data
        if (!kids) return null
        for (var i = 0; i < kids.length; i++) {
            var found = findListViewRecursive(kids[i])
            if (found) return found
        }
        return null
    }

    function findHighlighterRecursive(parentItem) {
        if (!parentItem) return null
        var kids = parentItem.data
        if (!kids) return null
        for (var i = 0; i < kids.length; i++) {
            var item = kids[i]
            if (item && item.hasOwnProperty("focusedColor") && item.hasOwnProperty("selectedColor")) {
                if (!item.hasOwnProperty("showSelectedOnly") || item.showSelectedOnly === false) {
                    highlightItem = item
                    origFocusColor = item.focusedColor
                    origSelectedColor = item.selectedColor
                    if (item.hasOwnProperty("color")) origBaseColor = item.color
                    return item
                }
            }
            var found = findHighlighterRecursive(item)
            if (found) return found
        }
        return null
    }

    function applyCustomColors() {
        if (!highlightItem) {
            var container = iface.findItemByObjectName("mapCanvasContainer")
            if (container) findHighlighterRecursive(container)
        }
        if (highlightItem) {
            highlightItem.focusedColor = targetFocusColor
            highlightItem.selectedColor = targetSelectedColor
            if (highlightItem.hasOwnProperty("color")) highlightItem.color = targetSelectedColor
        }
        if (qgisProject) qgisProject.selectionColor = targetSelectedColor
        if (mapCanvas) mapCanvas.refresh()
    }

    function restoreOriginalColors() {
        if (highlightItem) {
            highlightItem.focusedColor = origFocusColor
            highlightItem.selectedColor = origSelectedColor
            if (highlightItem.hasOwnProperty("color")) highlightItem.color = origBaseColor
        }
        if (qgisProject) qgisProject.selectionColor = origProjectColor
        if (mapCanvas) mapCanvas.refresh()
    }

    // === TIMERS ===
    Timer {
        id: computeCentroidsTimer
        interval: 400
        repeat: false
        onTriggered: { if (!sourceIsPoints && filter1Enabled) computeCentroids() }
    }

    Timer {
        id: computeCentroidsTimer2
        interval: 400
        repeat: false
        onTriggered: { if (!sourceIsPoints2 && filter2Enabled) computeCentroids2() }
    }

    Timer {
        id: uiStateWatcher
        interval: 250; running: isFormVisible && (filterActive || filterActive2); repeat: true
        onTriggered: {
            if (!featureFormItem) return
            if (!internalListView) internalListView = findListViewRecursive(featureFormItem)
            if (internalListView) {
                var isListNowVisible = (internalListView.visible === true && internalListView.opacity > 0)
                if (!wasListVisible && isListNowVisible) {
                    useListOffset = false; isReturnAction = true; zoomTimer.restart()
                }
                wasListVisible = isListNowVisible
            }
        }
    }

    Timer { id: searchDelayTimer; interval: 500; repeat: false; onTriggered: performDynamicSearch() }
    Timer { id: searchDelayTimer2; interval: 500; repeat: false; onTriggered: performDynamicSearch2() }

    Timer {
        id: zoomTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (filterToolRoot.pendingDriveMeLayer !== null) {
                var layer = filterToolRoot.pendingDriveMeLayer
                var bbox = layer.boundingBoxOfSelected()
                if (bbox) {
                    try {
                        var destCrs = mapCanvas.mapSettings.destinationCrs
                        var featExtent = GeometryUtils.reprojectRectangle(bbox, layer.crs, destCrs)
                        drivemeTool.startWithLayerAndExtent(layer, featExtent || bbox)
                    } catch(e) {
                        drivemeTool.startWithLayerAndExtent(layer, bbox)
                    }
                } else {
                    drivemeTool.startWithLayerAndExtent(layer, mapCanvas.mapSettings.extent)
                }
                filterToolRoot.pendingDriveMeLayer = null
            } else {
                performZoom()
            }
        }
    }

    Timer {
        id: openListTimer; interval: 250; repeat: false
        onTriggered: {
            if (featureFormItem && pendingFormLayer && pendingFormExpr) {
                try {
                    featureFormItem.model.setFeatures(pendingFormLayer, pendingFormExpr)
                    if (featureFormItem.extentController) featureFormItem.extentController.autoZoom = true
                    featureFormItem.show()
                    pendingFormLayer = null; pendingFormExpr = ""
                } catch(e) {}
            }
        }
    }

    // === GESTION FILTRE 1 ===
    function openFilterUI() {
        updateLayers()
        if (savedLayerName) {
            var layer = getLayerByName(savedLayerName)
            if (layer) {
                selectedLayer = layer
                checkSourceGeometryType()
                updateFields()
                if (savedFieldName) {
                    var fields = getFields(selectedLayer)
                    var idx = fields.indexOf(savedFieldName)
                    fieldSelector.currentIndex = idx >= 0 ? idx : 0
                }
            }
        }
        if (valueField) valueField.text = savedFilterText

        // Filtre 2 ouverture
        if (savedLayerName2) {
            var layer2 = getLayerByName(savedLayerName2)
            if (layer2) {
                selectedLayer2 = layer2
                checkSourceGeometryType2()
                updateFields2()
                if (savedFieldName2) {
                    var fields2 = getFields(selectedLayer2)
                    var idx2 = fields2.indexOf(savedFieldName2)
                    fieldSelector2.currentIndex = idx2 >= 0 ? idx2 : 0
                }
            }
        }
        if (valueField2) valueField2.text = savedFilterText2

        // --- Réévaluation forcée de l'état des boutons pour les 2 filtres ---
        updateApplyState()
        updateApplyState2()

        searchDialog.open()
    }

    function removeAllFilters(silent) {
        if (!sourceIsPoints) clearCentroids()
        restoreOriginalColors()
        if (selectedLayer) {
            try { selectedLayer.subsetString = ""; selectedLayer.removeSelection(); selectedLayer.triggerRepaint() } catch (_) {}
        }
        filterActive = false; showAllFeatures = false
        savedLayerName = ""; savedFieldName = ""; savedFilterText = ""; savedExpr = ""
        selectedLayer = null
        mapCanvas.refresh()
        updateLayers()

        valueField.text = ""

        updateApplyState()
        if (drivemeTool.isNavigating) drivemeTool.stopNavigation()
        
        if (!silent) {
            mainWindow.displayToast(tr("Filter 1 deleted"))
        }
    }

    function removeAllFilters2() {
        if (!sourceIsPoints2) clearCentroids2()
        if (selectedLayer2) {
            try { selectedLayer2.subsetString = ""; selectedLayer2.removeSelection(); selectedLayer2.triggerRepaint() } catch (_) {}
        }
        filterActive2 = false; showAllFeatures2 = false
        savedLayerName2 = ""; savedFieldName2 = ""; savedFilterText2 = ""; savedExpr2 = ""
        selectedLayer2 = null
        mapCanvas.refresh()
        updateLayers()

        valueField2.text = ""

        updateApplyState2()
        mainWindow.displayToast(tr("Filter 2 deleted"))
    }

    function performZoom() {
        var activeSelLayer = (searchStack.currentIndex === 1) ? selectedLayer2 : selectedLayer
        if (!activeSelLayer) return
        var bbox = activeSelLayer.boundingBoxOfSelected()

        if (bbox === undefined || bbox === null || bbox.xMinimum > bbox.xMaximum) {
            var features = activeSelLayer.selectedFeatures()
            if (features && features.length > 0) {
                if (features[0].geometry) bbox = features[0].geometry.boundingBox
            }
        }

        if (!bbox || isNaN(bbox.xMinimum) || isNaN(bbox.yMinimum) || (bbox.xMinimum === 0 && bbox.xMaximum === 0)) {
            return
        }

        if (bbox.width === 0 && bbox.height === 0) {
            var epsilon = 0.00001
            bbox.xMinimum -= epsilon; bbox.xMaximum += epsilon
            bbox.yMinimum -= epsilon; bbox.yMaximum += epsilon
        }

        if (!bbox) return

        try {
            var destCrs = mapCanvas.mapSettings.destinationCrs
            var finalExtent = GeometryUtils.reprojectRectangle(bbox, activeSelLayer.crs, destCrs)
            if (!finalExtent) return

            var cx = (finalExtent.xMinimum + finalExtent.xMaximum) / 2.0
            var cy = (finalExtent.yMinimum + finalExtent.yMaximum) / 2.0
            var minSize = (Math.abs(cx) > 180) ? 200.0 : 0.002

            if (finalExtent.width < minSize) {
                finalExtent.xMinimum = cx - (minSize / 2.0); finalExtent.xMaximum = cx + (minSize / 2.0)
            }
            if (finalExtent.height < minSize) {
                finalExtent.yMinimum = cy - (minSize / 2.0); finalExtent.yMaximum = cy + (minSize / 2.0)
            }

            var currentMapExtent = mapCanvas.mapSettings.extent
            var screenRatio = currentMapExtent.width / currentMapExtent.height
            var h = (finalExtent.height === 0) ? 0.001 : finalExtent.height
            var geomRatio = finalExtent.width / h
            var marginScale = 1.05
            var nw = 0, nh = 0

            if (geomRatio > screenRatio) {
                nw = finalExtent.width * marginScale; nh = nw / screenRatio
            } else {
                nh = finalExtent.height * marginScale; nw = nh * screenRatio
            }

            if (isReturnAction) { nw = nw * 0.65; nh = nh * 0.65; isReturnAction = false }
            
            var currentShowList = (searchStack.currentIndex === 1) ? showFeatureList2 : showFeatureList
            if (currentShowList && useListOffset) cy = cy - (nh * 0.25)

            finalExtent.xMinimum = cx - (nw / 2.0); finalExtent.xMaximum = cx + (nw / 2.0)
            finalExtent.yMinimum = cy - (nh / 2.0); finalExtent.yMaximum = cy + (nh / 2.0)

            mapCanvas.mapSettings.setExtent(finalExtent, true)

            var isPoints = (searchStack.currentIndex === 1) ? sourceIsPoints2 : sourceIsPoints
            if (isPoints) {
                activeSelLayer.removeSelection()
            }

            mapCanvas.refresh()
            applyCustomColors()
        } catch (e) {}
    }

    function applyFilter(allowFormOpen, doZoom) {
        if (!filter1Enabled) {
            if (selectedLayer) {
                selectedLayer.subsetString = ""
                selectedLayer.removeSelection()
                selectedLayer.triggerRepaint()
                mapCanvas.refresh()
            }
            filterActive = false
            return
        }

        var fieldToUse = (fieldSelector.currentText && fieldSelector.currentText !== tr("Select a field")) ? fieldSelector.currentText : savedFieldName
        if (!selectedLayer || !fieldToUse || !valueField.text) return
        if (allowFormOpen === undefined) allowFormOpen = true
        if (doZoom === undefined) doZoom = true

        try {
            savedLayerName = selectedLayer.name
            savedFieldName = fieldToUse
            savedFilterText = valueField.text

            if (!sourceIsPoints) clearCentroids()

            var values = savedFilterText.split(";").map(function(v) { return escapeValue(v.toLowerCase().trim()) }).filter(function(v) { return v.length > 0 })
            if (values.length === 0) return

            var expr = values.map(function(v) { return 'lower("' + savedFieldName + '") LIKE \'%' + v + '%\'' }).join(" OR ")
            savedExpr = expr

            selectedLayer.subsetString = showAllFeatures ? "" : expr
            selectedLayer.removeSelection()

            if (colorize1Enabled) {
                mapCanvas.mapSettings.selectionColor = targetSelectedColor
                selectedLayer.selectByExpression(expr)
            }

            // Pour les couches de points, on ne rafraîchit pas tant que la sélection
            // (créée juste au-dessus, éventuellement utile au calcul du zoom) n'a pas
            // été retirée — sinon le jaune apparaît brièvement à l'écran avant nettoyage.
            if (!sourceIsPoints) {
                selectedLayer.triggerRepaint()
                mapCanvas.refresh()
            }

            if (showFeatureList && featureFormItem && selectedLayer === getLayerByName(savedLayerName)) {
                pendingFormLayer = selectedLayer; pendingFormExpr = expr; openListTimer.restart()
            }

            var currentAutoZoom = (searchStack.currentIndex === 0) ? doAutoZoom : doAutoZoom2
            if (doZoom && currentAutoZoom) { useListOffset = true; isReturnAction = false; zoomTimer.start() }
            else if (sourceIsPoints && selectedLayer) {
                selectedLayer.removeSelection()
                selectedLayer.triggerRepaint()
                mapCanvas.refresh()
            }
            filterActive = true

            if (!sourceIsPoints) computeCentroidsTimer.restart()
        } catch(e) {}
    }

    function applyFilter2(allowFormOpen, doZoom) {
        if (!filter2Enabled) {
            if (selectedLayer2) {
                selectedLayer2.subsetString = ""
                selectedLayer2.removeSelection()
                selectedLayer2.triggerRepaint()
                mapCanvas.refresh()
            }
            filterActive2 = false
            return
        }

        var fieldToUse = (fieldSelector2.currentText && fieldSelector2.currentText !== tr("Select a field")) ? fieldSelector2.currentText : savedFieldName2
        if (!selectedLayer2 || !fieldToUse || !valueField2.text) return
        if (allowFormOpen === undefined) allowFormOpen = true
        if (doZoom === undefined) doZoom = true

        try {
            savedLayerName2 = selectedLayer2.name
            savedFieldName2 = fieldToUse
            savedFilterText2 = valueField2.text

            if (!sourceIsPoints2) clearCentroids2()

            var values = savedFilterText2.split(";").map(function(v) { return escapeValue(v.toLowerCase().trim()) }).filter(function(v) { return v.length > 0 })
            if (values.length === 0) return

            var expr = values.map(function(v) { return 'lower("' + savedFieldName2 + '") LIKE \'%' + v + '%\'' }).join(" OR ")
            savedExpr2 = expr

            selectedLayer2.subsetString = showAllFeatures2 ? "" : expr
            selectedLayer2.removeSelection()

            if (colorize2Enabled) {
                mapCanvas.mapSettings.selectionColor = targetSelectedColor
                selectedLayer2.selectByExpression(expr)
            }

            if (!sourceIsPoints2) {
                selectedLayer2.triggerRepaint()
                mapCanvas.refresh()
            }

            if (showFeatureList2 && featureFormItem && selectedLayer2 === getLayerByName(savedLayerName2)) {
                pendingFormLayer = selectedLayer2; pendingFormExpr = expr; openListTimer.restart()
            }

            if (doZoom && doAutoZoom2) { useListOffset = true; isReturnAction = false; zoomTimer.start() }
            else if (sourceIsPoints2 && selectedLayer2) {
                selectedLayer2.removeSelection()
                selectedLayer2.triggerRepaint()
                mapCanvas.refresh()
            }

            filterActive2 = true

            if (!sourceIsPoints2) computeCentroidsTimer2.restart()
        } catch(e) {}
    }

    // === UI UTILS ===
    function updateLayers() {
        var layers = ProjectUtils.mapLayers(qgisProject)
        var names = []
        for (var id in layers) if (layers[id] && layers[id].type === 0) names.push(layers[id].name)
        names.sort()
        var names2 = names.slice()
        
        if (!filterActive) names.unshift(tr("Select a layer"))
        if (layerSelector) {
            layerSelector.model = names
            if (filterActive && savedLayerName) {
                var idx = names.indexOf(savedLayerName)
                layerSelector.currentIndex = idx >= 0 ? idx : 0
            } else layerSelector.currentIndex = 0
        }

        if (!filterActive2) names2.unshift(tr("Select a layer"))
        if (layerSelector2) {
            layerSelector2.model = names2
            if (filterActive2 && savedLayerName2) {
                var idx2 = names2.indexOf(savedLayerName2)
                layerSelector2.currentIndex = idx2 >= 0 ? idx2 : 0
            } else layerSelector2.currentIndex = 0
        }
    }

    function getLayerByName(name) {
        var layers = ProjectUtils.mapLayers(qgisProject)
        for (var id in layers) if (layers[id].name === name) return layers[id]
        return null
    }

    function getFields(layer) {
        if (!layer || !layer.fields) return []
        var fields = layer.fields
        return fields.names ? fields.names.slice().sort() : []
    }

    function updateFields() {
        if (!selectedLayer) {
            fieldSelector.model = [tr("Select a field")]
            fieldSelector.currentIndex = 0; return
        }
        var fields = getFields(selectedLayer)
        if (!filterActive) fields.unshift(tr("Select a field"))
        fieldSelector.model = fields
        if (filterActive && savedFieldName) {
            var idx = fields.indexOf(savedFieldName)
            fieldSelector.currentIndex = idx >= 0 ? idx : 0
        } else {
            fieldSelector.currentIndex = 0; valueField.model = []
        }
        updateApplyState()
    }

    function updateFields2() {
        if (!selectedLayer2) {
            fieldSelector2.model = [tr("Select a field")]
            fieldSelector2.currentIndex = 0; return
        }
        var fields = getFields(selectedLayer2)
        if (!filterActive2) fields.unshift(tr("Select a field"))
        fieldSelector2.model = fields
        if (filterActive2 && savedFieldName2) {
            var idx = fields.indexOf(savedFieldName2)
            fieldSelector2.currentIndex = idx >= 0 ? idx : 0
        } else {
            fieldSelector2.currentIndex = 0; valueField2.model = []
        }
        updateApplyState2()
    }

    function performDynamicSearch() {
        var rawText = valueField.text
        var parts = rawText.split(";")
        var searchText = parts[parts.length - 1].trim()
        var uiName = fieldSelector.currentText

        if (!selectedLayer || uiName === tr("Select a field") || searchText === "") {
            valueField.model = []; suggestionPopup.close(); return
        }

        valueField.isLoading = true
        var names = selectedLayer.fields.names
        var logicalIndex = -1
        for (var i = 0; i < names.length; i++) { if (names[i] === uiName) { logicalIndex = i; break } }
        if (logicalIndex === -1) { valueField.isLoading = false; return }

        var realIndex = -1
        var attributes = selectedLayer.attributeList()
        if (attributes && logicalIndex < attributes.length) realIndex = attributes[logicalIndex]
        else realIndex = logicalIndex + 1

        var uniqueValues = {}; var valuesArray = []
        try {
            var expression = "\"" + uiName + "\" ILIKE '%" + searchText.replace(/'/g, "''") + "%'"
            var feature_iterator = LayerUtils.createFeatureIteratorFromExpression(selectedLayer, expression)
            var count = 0; var max_scan = 5000

            while (feature_iterator.hasNext() && count < 50 && max_scan > 0) {
                var feature = feature_iterator.next()
                var val = feature.attribute(realIndex)
                if (val === undefined) val = feature.attribute(uiName)
                if (val !== null && val !== undefined) {
                    var strVal = String(val).trim()
                    if (strVal !== "" && strVal !== "NULL") {
                        var exists = false
                        for(var p=0;p<parts.length-1;p++) if(parts[p].trim()===strVal) exists=true
                        if(!uniqueValues[strVal] && !exists) { uniqueValues[strVal]=true; valuesArray.push(strVal); count++ }
                    }
                }
                max_scan--
            }
            valuesArray.sort()
            valueField.model = valuesArray
            if (valuesArray.length > 0) suggestionPopup.open()
            else suggestionPopup.close()
        } catch (e) {}
        valueField.isLoading = false
    }

    function performDynamicSearch2() {
        var rawText = valueField2.text
        var parts = rawText.split(";")
        var searchText = parts[parts.length - 1].trim()
        var uiName = fieldSelector2.currentText

        if (!selectedLayer2 || uiName === tr("Select a field") || searchText === "") {
            valueField2.model = []; suggestionPopup2.close(); return
        }

        valueField2.isLoading = true
        var names = selectedLayer2.fields.names
        var logicalIndex = -1
        for (var i = 0; i < names.length; i++) { if (names[i] === uiName) { logicalIndex = i; break } }
        if (logicalIndex === -1) { valueField2.isLoading = false; return }

        var realIndex = -1
        var attributes = selectedLayer2.attributeList()
        if (attributes && logicalIndex < attributes.length) realIndex = attributes[logicalIndex]
        else realIndex = logicalIndex + 1

        var uniqueValues = {}; var valuesArray = []
        try {
            var expression = "\"" + uiName + "\" ILIKE '%" + searchText.replace(/'/g, "''") + "%'"
            var feature_iterator = LayerUtils.createFeatureIteratorFromExpression(selectedLayer2, expression)
            var count = 0; var max_scan = 5000

            while (feature_iterator.hasNext() && count < 50 && max_scan > 0) {
                var feature = feature_iterator.next()
                var val = feature.attribute(realIndex)
                if (val === undefined) val = feature.attribute(uiName)
                if (val !== null && val !== undefined) {
                    var strVal = String(val).trim()
                    if (strVal !== "" && strVal !== "NULL") {
                        var exists = false
                        for(var p=0;p<parts.length-1;p++) if(parts[p].trim()===strVal) exists=true
                        if(!uniqueValues[strVal] && !exists) { uniqueValues[strVal]=true; valuesArray.push(strVal); count++ }
                    }
                }
                max_scan--
            }
            valuesArray.sort()
            valueField2.model = valuesArray
            if (valuesArray.length > 0) suggestionPopup2.open()
            else suggestionPopup2.close()
        } catch (e) {}
        valueField2.isLoading = false
    }

    function updateApplyState() {
        if (!applyButton) return;
        
        var hasLayer = selectedLayer !== null && layerSelector.currentText !== tr("Select a layer");
        var hasField = fieldSelector && fieldSelector.currentText && fieldSelector.currentText !== tr("Select a field");
        var hasText = valueField && valueField.text && valueField.text.trim().length > 0;

        var isReady = hasLayer && hasField && hasText;

        applyButton.enabled = isReady;
        if (filterAndDriveButton) filterAndDriveButton.enabled = isReady;
    }

    function updateApplyState2() {
        if (!applyButton2) return;

        var hasLayer = selectedLayer2 !== null && layerSelector2.currentText !== tr("Select a layer");
        var hasField = fieldSelector2 && fieldSelector2.currentText && fieldSelector2.currentText !== tr("Select a field");
        var hasText = valueField2 && valueField2.text && valueField2.text.trim().length > 0;

        var isReady = hasLayer && hasField && hasText;

        applyButton2.enabled = isReady;
        if (filterAndDriveButton2) filterAndDriveButton2.enabled = isReady;
    }

    function escapeValue(value) { return value.trim().replace(/'/g, "''") }

    function tr(text) {
        var isFr = Qt.locale().name.substring(0, 2) === "fr"
        var dic = {
            "FILTERS": "FILTRES",
            "Filter 1": "Filtre 1",
            "Filter 2": "Filtre 2",
            "Filter 1 deleted": "Filtre 1 supprimé",
            "Filter 2 deleted": "Filtre 2 supprimé",
            "Filters 1 and 2 deleted": "Filtres 1 et 2 supprimés",
            "Select a layer": "Sélectionnez une couche",
            "Select a field": "Sélectionnez un champ",
            "Filter value(s) (separate by ;) :": "Valeur(s) du filtre (séparer par ;) :",
            "Type to search (ex: Paris; Lyon)...": "Tapez pour rechercher (ex: Paris; Lyon)...",
            "Show all geometries (+filtered)": "Afficher toutes géométries (+filtrées)",
            "Show feature list": "Afficher liste des entités",
            "Filter 1:\nACTIVE": "Filtre 1: \nACTIF",
            "Filter 2:\nACTIVE": "Filtre 2:\nACTIF",
            "Filter 1:\nINACTIVE": "Filtre 1:\nINACTIF",
            "Filter 2:\nINACTIVE": "Filtre 2:\nINACTIF",
            "Colorize\nFilter 1: ": "Colorier\nFiltre 1: ",
            "Colorize\nFilter 2: ": "Colorier\nFiltre 2: ",
            "YES": "OUI",
            "NO": "NON",
            "Apply filter": "Appliquer le filtre",
            "Filter & Drive me": "Appliquer le filtre & Montre-moi la route",
            "Zoom to filtered geometries": "Zoomer sur les géométries filtrées",
            "Delete filter": "Supprimer le filtre"
        }
        return isFr && dic[text] ? dic[text] : text
    }

    // === CONNEXIONS UI ===
    Connections {
        target: featureFormItem; ignoreUnknownSignals: true
        function onVisibleChanged() {
            filterToolRoot.isFormVisible = featureFormItem.visible
            if (!featureFormItem.visible) {
                internalListView = null; 
                wasListVisible = true; 
                showFeatureList = false; 
                showFeatureList2 = false

                var isPoints = (searchStack.currentIndex === 1) ? sourceIsPoints2 : sourceIsPoints
                if (isPoints) {
                    zoomTimer.stop()
                    isReturnAction = false
                    useListOffset = false
                    if (selectedLayer && sourceIsPoints) selectedLayer.removeSelection()
                    if (selectedLayer2 && sourceIsPoints2) selectedLayer2.removeSelection()
                }
            }
        }
        function onFeatureSelected(feature) {
            if (feature) {
                var activeSelLayer = (searchStack.currentIndex === 1) ? selectedLayer2 : selectedLayer
                if (activeSelLayer) {
                    activeSelLayer.removeSelection(); activeSelLayer.select(feature.id)
                    applyCustomColors()
                    useListOffset = true; isReturnAction = false; zoomTimer.start()
                }
            }
        }
    }

    // === RENDERERS CONTOURS FILTRE 1 ===
    Repeater {
        id: outlineRenderers
        model: filterToolRoot.outlinePolygons
        QFieldItems.GeometryRenderer {
            parent: mapCanvas
            mapSettings: mapCanvas.mapSettings
            geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
            geometryWrapper.qgsGeometry: modelData.geom
            lineWidth: 2
            color: filterToolRoot.colorPalette[modelData.colorIdx]
            opacity: filterToolRoot.filterActive && filterToolRoot.filter1Enabled && filterToolRoot.colorize1Enabled && !filterToolRoot.sourceIsPoints ? 0.75 : 0.0
        }
    }

    // === RENDERERS CONTOURS FILTRE 2 ===
    Repeater {
        id: outlineRenderers2
        model: filterToolRoot.outlinePolygons2
        QFieldItems.GeometryRenderer {
            parent: mapCanvas
            mapSettings: mapCanvas.mapSettings
            geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
            geometryWrapper.qgsGeometry: modelData.geom
            lineWidth: 2
            color: filterToolRoot.colorPalette2[modelData.colorIdx]
            opacity: filterToolRoot.filterActive2 && filterToolRoot.filter2Enabled && filterToolRoot.colorize2Enabled && !filterToolRoot.sourceIsPoints2 ? 0.75 : 0.0
        }
    }

    Connections {
        target: mapCanvas ? mapCanvas.mapSettings : null
        ignoreUnknownSignals: true
        function onExtentChanged() {
            if (filterToolRoot.filterActive && filterToolRoot.filter1Enabled && !filterToolRoot.sourceIsPoints && filterToolRoot.centroidPoints.length > 0)
                filterToolRoot.buildClusters()
            if (filterToolRoot.filterActive2 && filterToolRoot.filter2Enabled && !filterToolRoot.sourceIsPoints2 && filterToolRoot.centroidPoints2.length > 0)
                filterToolRoot.buildClusters2()
        }
    }

    // === CENTROÏDES FILTRE 1 ===
    Repeater {
        id: centroidItems
        model: filterToolRoot.clusteredPoints
        Item {
            parent: mapCanvas
            CoordinateTransformer {
                id: ct
                sourceCrs: CoordinateReferenceSystemUtils.wgs84Crs()
                destinationCrs: mapCanvas.mapSettings.destinationCrs
                transformContext: qgisProject ? qgisProject.transformContext : CoordinateReferenceSystemUtils.emptyTransformContext()
                sourcePosition: {
                    var g = GeometryUtils.createGeometryFromWkt("POINT(" + modelData.x + " " + modelData.y + ")")
                    return g ? GeometryUtils.centroid(g) : null
                }
            }
            MapToScreen {
                id: mts
                mapSettings: mapCanvas.mapSettings
                mapPoint: ct.projectedPosition
            }
            Rectangle {
                x: mts.screenPoint.x - width / 2; y: mts.screenPoint.y - height / 2
                width: modelData.clusterCount > 1 ? 22 : 12; height: modelData.clusterCount > 1 ? 22 : 12
                radius: modelData.clusterCount > 1 ? 11 : 6
                color: filterToolRoot.colorPalette[modelData.colorIdx]
                border.color: modelData.clusterCount > 1 ? "yellow" : "white"
                border.width: modelData.clusterCount > 1 ? 2 : 1.5
                visible: filterToolRoot.filterActive && filterToolRoot.filter1Enabled && filterToolRoot.colorize1Enabled && !filterToolRoot.sourceIsPoints
                Text {
                    anchors.centerIn: parent
                    text: modelData.clusterCount > 1 ? modelData.clusterCount : ""
                    color: "white"; font.bold: true; font.pixelSize: 10
                    visible: modelData.clusterCount > 1
                }
            }
        }
    }

    // === CENTROÏDES FILTRE 2 ===
    Repeater {
        id: centroidItems2
        model: filterToolRoot.clusteredPoints2
        Item {
            parent: mapCanvas
            CoordinateTransformer {
                id: ct2
                sourceCrs: CoordinateReferenceSystemUtils.wgs84Crs()
                destinationCrs: mapCanvas.mapSettings.destinationCrs
                transformContext: qgisProject ? qgisProject.transformContext : CoordinateReferenceSystemUtils.emptyTransformContext()
                sourcePosition: {
                    var g = GeometryUtils.createGeometryFromWkt("POINT(" + modelData.x + " " + modelData.y + ")")
                    return g ? GeometryUtils.centroid(g) : null
                }
            }
            MapToScreen {
                id: mts2
                mapSettings: mapCanvas.mapSettings
                mapPoint: ct2.projectedPosition
            }
            Rectangle {
                x: mts2.screenPoint.x - width / 2; y: mts2.screenPoint.y - height / 2
                width: modelData.clusterCount > 1 ? 22 : 12; height: modelData.clusterCount > 1 ? 22 : 12
                radius: modelData.clusterCount > 1 ? 11 : 6
                color: filterToolRoot.colorPalette2[modelData.colorIdx]
                border.color: modelData.clusterCount > 1 ? "yellow" : "white"
                border.width: modelData.clusterCount > 1 ? 2 : 1.5
                visible: filterToolRoot.filterActive2 && filterToolRoot.filter2Enabled && filterToolRoot.colorize2Enabled && !filterToolRoot.sourceIsPoints2
                Text {
                    anchors.centerIn: parent
                    text: modelData.clusterCount > 1 ? modelData.clusterCount : ""
                    color: "white"; font.bold: true; font.pixelSize: 10
                    visible: modelData.clusterCount > 1
                }
            }
        }
    }

    // === DIALOGUE PRINCIPAL AVEC ONGLETS ===
    Dialog {
        id: searchDialog
        parent: mainWindow.contentItem
        modal: true

        width: Math.min(mainWindow.width * 0.95, 450)
        height: Math.min(innerCol.implicitHeight + 10, mainWindow.height * 0.92)

        x: (mainWindow.width - width) / 2
        y: (mainWindow.height - height) / 2

        background: Rectangle {
            color: "white"
            border.color: Theme.mainColor
            border.width: 2
            radius: 8
        }

        contentItem: ColumnLayout {
            id: innerCol
            anchors.fill: parent
            spacing: 5

            Label {
                text: tr("FILTERS")
                font.bold: true
                font.pointSize: 18
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                Layout.topMargin: 10
            }

            // --- BARRE D'ONGLETS ---
            TabBar {
                id: searchBar
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4

                TabButton { 
                    id: btnFilter1
                    text: tr("Filter 1")
                    contentItem: Text {
                        text: btnFilter1.text
                        font.pixelSize: 14
                        font.bold: btnFilter1.checked
                        color: btnFilter1.checked ? Theme.mainColor : "#555"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 45
                        color: btnFilter1.checked ? "#f0f9f0" : "#f8f8f8"
                        border.color: btnFilter1.checked ? Theme.mainColor : "transparent"
                        border.width: btnFilter1.checked ? 2 : 0
                        radius: 6
                    }
                }

                TabButton { 
                    id: btnFilter2
                    text: tr("Filter 2")
                    contentItem: Text {
                        text: btnFilter2.text
                        font.pixelSize: 14
                        font.bold: btnFilter2.checked
                        color: btnFilter2.checked ? Theme.mainColor : "#555"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 45
                        color: btnFilter2.checked ? "#f0f9f0" : "#f8f8f8"
                        border.color: btnFilter2.checked ? Theme.mainColor : "transparent"
                        border.width: btnFilter2.checked ? 2 : 0
                        radius: 6 
                    }
                }
            } 

            // --- SWITCH D'ACTIVATION DU FILTRE ACTIF — fixe sous les onglets,
            // hors du ScrollView pour ne jamais défiler avec le contenu ---
            // Filtre 1 : texte + switch alignés à gauche
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                visible: searchBar.currentIndex === 0

                Label {
                    text: filter1Enabled ? tr("Filter 1:\nACTIVE") : tr("Filter 1:\nINACTIVE")
                    font.bold: true
                }
                Switch {
                    id: filter1Switch
                    checked: filter1Enabled
                    onToggled: {
                        filter1Enabled = checked
                        if (checked) {
                            if (savedLayerName && layerSelector.find(savedLayerName) !== -1) {
                                layerSelector.currentIndex = layerSelector.find(savedLayerName)
                            }
                            if (savedFieldName && fieldSelector.find(savedFieldName) !== -1) {
                                fieldSelector.currentIndex = fieldSelector.find(savedFieldName)
                            }
                        }
                        applyFilter(true, false)
                    }
                }
                Label {
                    text: tr("Colorize\nFilter 1: ") + (colorize1Enabled ? tr("YES") : tr("NO"))
                    font.bold: true
                    Layout.leftMargin: 15
                }
                Switch {
                    id: colorize1Switch
                    checked: colorize1Enabled
                    onToggled: {
                        colorize1Enabled = checked
                        if (filterActive && selectedLayer) {
                            if (checked) {
                                mapCanvas.mapSettings.selectionColor = targetSelectedColor
                                // Pas de sélection sur couche de points : rien ne dépend
                                // de cette sélection ici (pas de contour/centroïde coloré
                                // pour les points), donc on ne recrée jamais de jaune visible
                                if (savedExpr && !sourceIsPoints) selectedLayer.selectByExpression(savedExpr)
                            } else {
                                selectedLayer.removeSelection()
                            }
                            selectedLayer.triggerRepaint()
                            mapCanvas.refresh()
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // Filtre 2 : texte + switch alignés à droite
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                visible: searchBar.currentIndex === 1

                Item { Layout.fillWidth: true }
                Label {
                    text: filter2Enabled ? tr("Filter 2:\nACTIVE") : tr("Filter 2:\nINACTIVE")
                    font.bold: true
                }
                Switch {
                    id: filter2Switch
                    checked: filter2Enabled
                    onToggled: {
                        filter2Enabled = checked
                        if (checked) {
                            if (savedLayerName2 && layerSelector2.find(savedLayerName2) !== -1) {
                                layerSelector2.currentIndex = layerSelector2.find(savedLayerName2)
                            }
                            if (savedFieldName2 && fieldSelector2.find(savedFieldName2) !== -1) {
                                fieldSelector2.currentIndex = fieldSelector2.find(savedFieldName2)
                            }
                        }
                        applyFilter2(true, false)
                    }
                }
                Label {
                    text: tr("Colorize\nFilter 2: ") + (colorize2Enabled ? tr("YES") : tr("NO"))
                    font.bold: true
                    Layout.leftMargin: 15
                }
                Switch {
                    id: colorize2Switch
                    checked: colorize2Enabled
                    onToggled: {
                        colorize2Enabled = checked
                        if (filterActive2 && selectedLayer2) {
                            if (checked) {
                                mapCanvas.mapSettings.selectionColor = targetSelectedColor
                                if (savedExpr2 && !sourceIsPoints2) selectedLayer2.selectByExpression(savedExpr2)
                            } else {
                                selectedLayer2.removeSelection()
                            }
                            selectedLayer2.triggerRepaint()
                            mapCanvas.refresh()
                        }
                    }
                }
            }

            // --- CONTENU DES ONGLETS ---
            StackLayout {
                id: searchStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: searchBar.currentIndex

                // ================ ONGLET 1 ====================
                ScrollView {
                    id: scrollView1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth

                    topPadding: 10
                    bottomPadding: 10
                    leftPadding: 20
                    rightPadding: 20

                    ColumnLayout {
                        width: scrollView1.availableWidth
                        spacing: 10

                        QfComboBox {
                            id: layerSelector; Layout.fillWidth: true; Layout.preferredHeight: 35; model: []
                            onCurrentTextChanged: {
                                savedExpr = ""; if (currentText === tr("Select a layer")) { selectedLayer=null; fieldSelector.model=[tr("Select a field")]; return }
                                selectedLayer = getLayerByName(currentText); updateFields(); checkSourceGeometryType()
                            }
                        }
                        QfComboBox {
                            id: fieldSelector; Layout.fillWidth: true; Layout.preferredHeight: 35; model: []
                            onActivated: { valueField.text=""; valueField.model=[]; updateApplyState() }
                            onCurrentTextChanged: updateApplyState()
                        }
                        Label { text: tr("Filter value(s) (separate by ;) :") }
                        TextField {
                            id: valueField; Layout.fillWidth: true; Layout.preferredHeight: 35
                            placeholderText: tr("Type to search (ex: Paris; Lyon)...")
                            property var model: []; property bool isLoading: false
                            onActiveFocusChanged: { if (activeFocus && text.trim().length > 0) { if (model.length>0) suggestionPopup.open(); else performDynamicSearch() } }
                            onTextChanged: { if(text.trim().length>0) searchDelayTimer.restart(); else {searchDelayTimer.stop(); suggestionPopup.close()} updateApplyState() }
                            Popup {
                                id: suggestionPopup; y: valueField.height; width: valueField.width; height: Math.min(listView.contentHeight+10, 200); padding: 1
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                                background: Rectangle { color: "white"; border.color: "#bdbdbd" }
                                ListView {
                                    id: listView; anchors.fill: parent; clip: true; model: valueField.model
                                    delegate: ItemDelegate {
                                        text: modelData; width: listView.width
                                        onClicked: {
                                            var txt=valueField.text; var last=txt.lastIndexOf(";")
                                            valueField.text = (last===-1 ? modelData : txt.substring(0, last+1)+" "+modelData) + " ; "
                                            suggestionPopup.close(); valueField.forceActiveFocus(); valueField.model=[]
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: -16
                            CheckBox {
                                id: showAllCheck; text: tr("Show all geometries (+filtered)"); checked: showAllFeatures; Layout.fillWidth: true
                                onToggled: { showAllFeatures = checked; if (filterActive) applyFilter(true, false) }
                            }
                            CheckBox {
                                id: showListCheck; text: tr("Show feature list"); checked: showFeatureList; Layout.fillWidth: true
                                onToggled: { showFeatureList = checked; if (filterActive && checked) applyFilter(true, false) }
                            }
                            CheckBox {
                                id: autoZoomCheck
                                text: tr("Zoom to filtered geometries")
                                checked: filterToolRoot.doAutoZoom
                                Layout.fillWidth: true
                                onToggled: filterToolRoot.doAutoZoom = checked
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            Button {
                                text: tr("Delete filter"); Layout.fillWidth: true; Layout.topMargin: 5
                                background: Rectangle { color: "#333333"; radius: 10 }
                                contentItem: Text { text: parent.text; color: "white"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                onClicked: { removeAllFilters(); searchDialog.close() }
                            }
                            Button {
                                id: applyButton; text: tr("Apply filter"); enabled: false; Layout.fillWidth: true; Layout.topMargin: 5
                                background: Rectangle { radius: 10; color: enabled ? "#80cc28" : "#e0e0e0" }
                                contentItem: Text { text: parent.text; color: enabled ? "white" : "#666666"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                onClicked: { applyFilter(true, true); searchDialog.close() }
                            }
                        }

                        Button {
                            id: filterAndDriveButton; text: tr("Filter & Drive me"); enabled: false; Layout.fillWidth: true
                            background: Rectangle { radius: 10; color: enabled ? "#80cc28" : "#e0e0e0" }
                            contentItem: Text { text: parent.text; color: enabled ? "white" : "#666666"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: {
                                filterToolRoot.pendingDriveMeLayer = selectedLayer
                                applyFilter(true, true)
                                searchDialog.close()
                            }
                        }
                    }
                }

                // =============== ONGLET 2 ====================
                ScrollView {
                    id: scrollView2
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth

                    topPadding: 10
                    bottomPadding: 10
                    leftPadding: 20
                    rightPadding: 20

                    ColumnLayout {
                        width: scrollView2.availableWidth
                        spacing: 10

                        QfComboBox {
                            id: layerSelector2; Layout.fillWidth: true; Layout.preferredHeight: 35; model: []
                            onCurrentTextChanged: {
                                savedExpr2 = ""; if (currentText === tr("Select a layer")) { selectedLayer2=null; fieldSelector2.model=[tr("Select a field")]; return }
                                selectedLayer2 = getLayerByName(currentText); updateFields2(); checkSourceGeometryType2()
                            }
                        }
                        QfComboBox {
                            id: fieldSelector2; Layout.fillWidth: true; Layout.preferredHeight: 35; model: []
                            onActivated: { valueField2.text=""; valueField2.model=[]; updateApplyState2() }
                            onCurrentTextChanged: updateApplyState2()
                        }
                        Label { text: tr("Filter value(s) (separate by ;) :") }
                        TextField {
                            id: valueField2; Layout.fillWidth: true; Layout.preferredHeight: 35
                            placeholderText: tr("Type to search (ex: Paris; Lyon)...")
                            property var model: []; property bool isLoading: false
                            onActiveFocusChanged: { if (activeFocus && text.trim().length > 0) { if (model.length>0) suggestionPopup2.open(); else performDynamicSearch2() } }
                            onTextChanged: { if(text.trim().length>0) searchDelayTimer2.restart(); else {searchDelayTimer2.stop(); suggestionPopup2.close()} updateApplyState2() }
                            Popup {
                                id: suggestionPopup2; y: valueField2.height; width: valueField2.width; height: Math.min(listView2.contentHeight+10, 200); padding: 1
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                                background: Rectangle { color: "white"; border.color: "#bdbdbd" }
                                ListView {
                                    id: listView2; anchors.fill: parent; clip: true; model: valueField2.model
                                    delegate: ItemDelegate {
                                        text: modelData; width: listView2.width
                                        onClicked: {
                                            var txt=valueField2.text; var last=txt.lastIndexOf(";")
                                            valueField2.text = (last===-1 ? modelData : txt.substring(0, last+1)+" "+modelData) + " ; "
                                            suggestionPopup2.close(); valueField2.forceActiveFocus(); valueField2.model=[]
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: -16
                            CheckBox {
                                id: showAllCheck2; text: tr("Show all geometries (+filtered)"); checked: showAllFeatures2; Layout.fillWidth: true
                                onToggled: { showAllFeatures2 = checked; if (filterActive2) applyFilter2(true, false) }
                            }
                            CheckBox {
                                id: showListCheck2; text: tr("Show feature list"); checked: showFeatureList2; Layout.fillWidth: true
                                onToggled: { showFeatureList2 = checked; if (filterActive2 && checked) applyFilter2(true, false) }
                            }
                            CheckBox {
                                id: autoZoomCheck2
                                text: tr("Zoom to filtered geometries")
                                checked: filterToolRoot.doAutoZoom2
                                Layout.fillWidth: true
                                onToggled: filterToolRoot.doAutoZoom2 = checked
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            Button {
                                text: tr("Delete filter"); Layout.fillWidth: true; Layout.topMargin: 5
                                background: Rectangle { color: "#333333"; radius: 10 }
                                contentItem: Text { text: parent.text; color: "white"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                onClicked: { removeAllFilters2(); searchDialog.close() }
                            }
                            Button {
                                id: applyButton2; text: tr("Apply filter"); enabled: false; Layout.fillWidth: true; Layout.topMargin: 5
                                background: Rectangle { radius: 10; color: enabled ? "#80cc28" : "#e0e0e0" }
                                contentItem: Text { text: parent.text; color: enabled ? "white" : "#666666"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                onClicked: { applyFilter2(true, true); searchDialog.close() }
                            }
                        }

                        Button {
                            id: filterAndDriveButton2; text: tr("Filter & Drive me"); enabled: false; Layout.fillWidth: true
                            background: Rectangle { radius: 10; color: enabled ? "#80cc28" : "#e0e0e0" }
                            contentItem: Text { text: parent.text; color: enabled ? "white" : "#666666"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: {
                                filterToolRoot.pendingDriveMeLayer = selectedLayer2
                                applyFilter2(true, true)
                                searchDialog.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
