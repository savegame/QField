/***************************************************************************
                            qgismobileapp.qml
                              -------------------
              begin                : 10.12.2014
              copyright            : (C) 2014 by Matthias Kuhn
              email                : matthias (at) opengis.ch
 ***************************************************************************/

/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Window 2.12
import QtGraphicalEffects 1.0
import Qt.labs.settings 1.0 as LabSettings
import QtQml 2.12

import org.qgis 1.0
import org.qfield 1.0
import Theme 1.0

import '.'
import 'geometry_editors'

ApplicationWindow {
  id: mainWindow
  objectName: 'mainWindow'
  visible: true

  LabSettings.Settings {
      property alias x: mainWindow.x
      property alias y: mainWindow.y
      property alias width: mainWindow.width
      property alias height: mainWindow.height

      Component.onCompleted: {
          width = Math.max(width, 50)
          height = Math.max(height, 50)
          x = Math.min(x, mainWindow.screen.width - width)
          y = Math.min(y, mainWindow.screen.height - height)
      }
  }

  FocusStack{
      id: focusstack
  }

  QuestionDialog{
    id: questionDialog
    parent: ApplicationWindow.overlay
  }

  //this keyHandler is because otherwise the back-key is not handled in the mainWindow. Probably this could be solved cuter.
  Item {
    id: keyHandler
    objectName: "keyHandler"

    visible: true
    focus: true

    property int previousVisibilityState: Window.Windowed

    Keys.onReleased: {
      if ( event.key === Qt.Key_Back || event.key === Qt.Key_Escape ) {
        if ( featureForm.visible ) {
            featureForm.hide();
        } else if ( stateMachine.state === 'measure' ) {
          mainWindow.closeMeasureTool()
        } else {
          mainWindow.close();
        }
        event.accepted = true
      } else if ( event.key === Qt.Key_F11 ) {
        if (Qt.platform.os !== "android" && Qt.platform.os !== "ios") {
          if (mainWindow.visibility !== Window.FullScreen) {
            previousVisibilityState = mainWindow.visibility;
            mainWindow.visibility = Window.FullScreen;
          } else {
            mainWindow.visibility = Window.Windowed;
            if (previousVisibilityState === Window.Maximized) {
              mainWindow.showMaximized();
            }
          }
        }
      }
    }

    Component.onCompleted: focusstack.addFocusTaker( this )
  }

  //currentRubberband provides the rubberband depending on the current state (digitize or measure)
  property Rubberband currentRubberband
  property LayerObserver layerObserverAlias: layerObserver
  property QgsGpkgFlusher gpkgFlusherAlias: gpkgFlusher

  signal closeMeasureTool()
  signal changeMode( string mode )

  Item {
    id: stateMachine

    property string lastState

    states: [
      State {
        name: "browse"
        PropertyChanges { target: identifyTool; deactivated: false }
      },

      State {
        name: "digitize"
        PropertyChanges { target: identifyTool; deactivated: false }
        PropertyChanges { target: mainWindow; currentRubberband: digitizingRubberband }
      },

      State {
        name: 'measure'
        PropertyChanges { target: identifyTool; deactivated: true }
        PropertyChanges { target: mainWindow; currentRubberband: measuringTool.measuringRubberband }
        PropertyChanges { target: featureForm; state: "Hidden" }
      }
    ]
    state: "browse"
  }

  onChangeMode: {
    if ( stateMachine.state == mode )
      return

    stateMachine.lastState = stateMachine.state
    stateMachine.state = mode
    switch ( stateMachine.state )
    {
      case 'browse':
        displayToast( qsTr( 'You are now in browse mode' ) );
        break;
      case 'digitize':
        dashBoard.ensureEditableLayerSelected();
        if (dashBoard.currentLayer)
        {
          displayToast( qsTr( 'You are now in digitize mode on layer %1' ).arg( dashBoard.currentLayer.name ) );
        }
        else
        {
          displayToast( qsTr( 'You are now in digitize mode' ) );
        }
        break;
      case 'measure':
        displayToast( qsTr( 'You are now in measure mode' ) );
        break;
    }
  }

  onCloseMeasureTool: {
    overlayFeatureFormDrawer.close()
    changeMode( stateMachine.lastState)
  }

  /**
   * The position source to access GNSS devices
   */
  Positioning {
    id: positionSource
    device: positioningSettings.positioningDevice

    property bool currentness: false;
    property alias destinationCrs: positionSource.coordinateTransformer.destinationCrs

    coordinateTransformer: CoordinateTransformer {
      destinationCrs: mapCanvas.mapSettings.destinationCrs
      transformContext: qgisProject ? qgisProject.transformContext : CoordinateReferenceSystemUtils.emptyTransformContext()
      deltaZ: positioningSettings.antennaHeightActivated ? positioningSettings.antennaHeight * -1 : 0
      skipAltitudeTransformation: positioningSettings.skipAltitudeCorrection
    }
  }

  Timer {
    id: positionTimer

    property bool geocoderLocatorFiltersChecked: false;

    interval: 2500
    repeat: true
    running: positionSource.active
    triggeredOnStart: true
    onTriggered: {
      if ( positionSource.positionInformation ) {
        positionSource.currentness = ( ( new Date() - positionSource.positionInformation.utcDateTime ) / 1000 ) < 30;
        if ( !geocoderLocatorFiltersChecked && positionSource.valid ) {
          locatorSettings.model.setGeocoderLocatorFiltersDefaulByPosition( positionSource.positionInformation );
          geocoderLocatorFiltersChecked = true;
        }
      }
    }
  }

  Item {
    id: mapCanvas
    clip: true
    property bool isBeingTouched: false

    DragHandler {
        id: freehandHandler
        property bool isDigitizing: false
        enabled: freehandButton.visible && freehandButton.freehandDigitizing && !digitizingToolbar.rubberbandModel.frozen && (!featureForm.visible || digitizingToolbar.geometryRequested)
        acceptedDevices: !qfieldSettings.mouseAsTouchScreen ? PointerDevice.Stylus | PointerDevice.Mouse : PointerDevice.Stylus
        grabPermissions: PointerHandler.CanTakeOverFromHandlersOfSameType | PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByAnything

        onActiveChanged: {
            if (!active) {
                var screenLocation = centroid.position;
                var screenFraction = settings.value( "/QField/Digitizing/FreehandRecenterScreenFraction", 5 );
                var threshold = Math.min( mainWindow.width, mainWindow.height ) / screenFraction;
                if ( screenLocation.x < threshold || screenLocation.x > mainWindow.width - threshold ||
                        screenLocation.y < threshold || screenLocation.y > mainWindow.height - threshold )
                {
                    mapCanvas.mapSettings.setCenter(mapCanvas.mapSettings.screenToCoordinate(screenLocation));
                }
            }
        }

        onCentroidChanged: {
            if (active) {
                if (geometryEditorsToolbar.canvasClicked(centroid.position)) {
                    // needed to handle freehand digitizing of rings
                } else {
                    digitizingToolbar.addVertex();
                }
            }
        }
    }

    HoverHandler {
        id: hoverHandler
        enabled: !qfieldSettings.mouseAsTouchScreen
                 && !gnssLockButton.linkActive
                 && !parent.isBeingTouched
                 && (!digitizingToolbar.rubberbandModel || !digitizingToolbar.rubberbandModel.frozen)
        acceptedDevices: PointerDevice.Stylus | PointerDevice.Mouse
        grabPermissions: PointerHandler.TakeOverForbidden

        onPointChanged: {
            function pointInItem(point, item) {
                var itemCoordinates = item.mapToItem(mainWindow.contentItem, 0, 0);
                return point.position.x >= itemCoordinates.x && point.position.x <= itemCoordinates.x + item.width &&
                       point.position.y >= itemCoordinates.y && point.position.y <= itemCoordinates.y + item.height;
            }
            // when hovering digitizing toolbars, reset coordinate locator position for nicer UX
            if ( !freehandHandler.active && pointInItem( point, digitizingToolbar ) ) {
                coordinateLocator.sourceLocation = mapCanvas.mapSettings.coordinateToScreen( digitizingToolbar.rubberbandModel.lastCoordinate );
            } else if ( !freehandHandler.active && pointInItem( point, geometryEditorsToolbar ) ) {
                coordinateLocator.sourceLocation = mapCanvas.mapSettings.coordinateToScreen( geometryEditorsToolbar.editorRubberbandModel.lastCoordinate );
            } else {
                // after a click, it seems that the position is sent once at 0,0 => weird
                if (point.position !== Qt.point(0, 0))
                    coordinateLocator.sourceLocation = point.position
            }
        }

        onActiveChanged: {
            if ( !active )
                coordinateLocator.sourceLocation = undefined

        }

        onHoveredChanged: {
            if ( !hovered )
                coordinateLocator.sourceLocation = undefined
        }
    }
    Timer {
        id: resetIsBeingTouchedTimer
        interval: 750
        repeat: false

        onTriggered: {
            parent.isBeingTouched = false
        }
    }
    /* The second hover handler is a workaround what appears to be an issue with
     * Qt whereas synthesized mouse event would trigger the first HoverHandler even though
     * PointerDevice.TouchScreen was explicitly taken out of the accepted devices.
     */
    HoverHandler {
        id: dummyHoverHandler
        enabled: !qfieldSettings.mouseAsTouchScreen
        acceptedDevices: PointerDevice.TouchScreen
        grabPermissions: PointerHandler.TakeOverForbidden

        onHoveredChanged: {
            if ( hovered ) {
                parent.isBeingTouched = true
                resetIsBeingTouchedTimer.stop()
            }
            else {
                resetIsBeingTouchedTimer.restart()
            }
        }
    }

    /* Initialize a MapSettings object. This will contain information about
     * the current canvas extent. It is shared between the base map and all
     * map canvas items and is used to transform map coordinates to pixel
     * coordinates.
     * It may change any time and items that hold a reference to this property
     * are responsible to handle this properly.
     */
    property MapSettings mapSettings: mapCanvasMap.mapSettings

    /* Placement and size. Share right anchor with featureForm */
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: informationView.visible ? informationView.top : parent.bottom

    Rectangle {
      id: mapCanvasBackground
      anchors.fill: parent
      color: mapCanvas.mapSettings.backgroundColor
    }

    /* The map canvas */
    MapCanvas {
      id: mapCanvasMap
      incrementalRendering: true
      freehandDigitizing: freehandButton.freehandDigitizing && freehandHandler.active

      anchors.fill: parent

      onClicked:  {
          if (featureForm.state == "FeatureFormEdit") {
              featureForm.requestCancel();
              return;
          }

          if (locatorItem.state == "on") {
              locatorItem.state = "off"
              return;
          }

          if ( type === "stylus" ) {
              // Check if geometry editor is taking over
              if ( !gnssLockButton.linkActive && geometryEditorsToolbar.canvasClicked(point) )
                  return;

              if ( !gnssLockButton.linkActive && (!featureForm.visible || digitizingToolbar.geometryRequested ) &&
                   ( ( stateMachine.state === "digitize" && digitizingFeature.currentLayer ) || stateMachine.state === 'measure' ) ) {
                  if ( Number( currentRubberband.model.geometryType ) === QgsWkbTypes.PointGeometry ||
                          Number( currentRubberband.model.geometryType ) === QgsWkbTypes.NullGeometry ) {
                      digitizingToolbar.confirm()
                  } else {
                      digitizingToolbar.addVertex()
                  }
              } else {
                  if (!overlayFeatureFormDrawer.visible || !featureForm.canvasOperationRequested) {
                      identifyTool.identify(point)
                  }
              }
          }
      }

      onConfirmedClicked: {
          if (!featureForm.canvasOperationRequested && !overlayFeatureFormDrawer.visible && featureForm.state != "FeatureFormEdit")
          {
              identifyTool.identify(point)
          }
      }

      onLongPressed: {
        if ( type === "stylus" ) {
          if (geometryEditorsToolbar.canvasLongPressed(point)) {
            // for instance, the vertex editor will select a vertex if possible
            return
          }
          if ( stateMachine.state === "digitize" && dashBoard.currentLayer ) { // the sourceLocation test checks if a (stylus) hover is active
            if ( ( Number( currentRubberband.model.geometryType ) === QgsWkbTypes.LineGeometry && currentRubberband.model.vertexCount >= 2 )
               || ( Number( currentRubberband.model.geometryType ) === QgsWkbTypes.PolygonGeometry && currentRubberband.model.vertexCount >= 2 ) ) {
                digitizingToolbar.addVertex();

                // When it's released, it will normally cause a release event to close the attribute form.
                // We get around this by temporarily switching the closePolicy.
                overlayFeatureFormDrawer.closePolicy = Popup.CloseOnEscape

                digitizingToolbar.confirm()
                return
            }
          }
          // do not use else, as if it was catch it has return before
          if( !overlayFeatureFormDrawer.visible ) {
            identifyTool.identify(point)
          }
        } else {
          canvasMenu.point = mapCanvas.mapSettings.screenToCoordinate(point)
          canvasMenu.popup(point.x, point.y)
        }
      }

      onLongPressReleased: {
        if ( type === "stylus" ) {
          // The user has released the long press. We can re-enable the default close behavior for the feature form.
          // The next press will be intentional to close the form.
          overlayFeatureFormDrawer.closePolicy = Popup.CloseOnEscape | Popup.CloseOnPressOutside
        }
      }
    }


  /**************************************************
   * Overlays, including:
   * - Coordinate Locator
   * - Location Marker
   * - Identify Highlight
   * - Digitizing Rubberband
   **************************************************/

    /** The identify tool **/
    IdentifyTool {
      id: identifyTool

      mapSettings: mapCanvas.mapSettings
      model: featureForm.model
      searchRadiusMm: 3
    }

    /** A rubberband for measuring **/
    MeasuringTool {
      id: measuringTool
      visible: stateMachine.state === 'measure'
      anchors.fill: parent

      measuringRubberband.model.currentCoordinate: coordinateLocator.currentCoordinate
      measuringRubberband.mapSettings: mapCanvas.mapSettings
    }

    /** Tracking sessions **/
    Repeater {
        id: trackings
        model: trackingModel
        Tracking {
        }
    }

    /** A rubberband for ditizing **/
    Rubberband {
      id: digitizingRubberband
      width: 2.5

      mapSettings: mapCanvas.mapSettings

      model: RubberbandModel {
        frozen: false
        currentCoordinate: coordinateLocator.currentCoordinate
        vectorLayer: digitizingToolbar.geometryRequested ? digitizingToolbar.geometryRequestedLayer : dashBoard.currentLayer
        crs: mapCanvas.mapSettings.destinationCrs
      }

      anchors.fill: parent
      visible: stateMachine.state === "digitize"
    }

    /** A rubberband for the different geometry editors **/
    Rubberband {
      id: geometryEditorsRubberband
      width: 2.5
      color: '#80000000'

      mapSettings: mapCanvas.mapSettings

      model: RubberbandModel {
        frozen: false
        currentCoordinate: coordinateLocator.currentCoordinate
        crs: mapCanvas.mapSettings.destinationCrs
        geometryType: QgsWkbTypes.LineGeometry
      }

      anchors.fill: parent
    }

    BookmarkHighlight {
        id: bookmarkHighlight
        mapSettings: mapCanvas.mapSettings
    }

    Navigation {
      id: navigation
      mapSettings: mapCanvas.mapSettings
      location: positionSource.active ? positionSource.projectedPosition : undefined
    }

    NavigationHighlight {
      id: navigationHighlight
      navigation: navigation
    }

    /** A coordinate locator for digitizing **/
    CoordinateLocator {
      id: coordinateLocator
      anchors.fill: parent
      visible: stateMachine.state === "digitize" || stateMachine.state === 'measure'
      highlightColor: digitizingToolbar.isDigitizing ? currentRubberband.color : "#CFD8DC"
      mapSettings: mapCanvas.mapSettings
      currentLayer: dashBoard.currentLayer
      positionInformation: positionSource.positionInformation
      positionLocked: positionSource.active && positioningSettings.positioningCoordinateLock
      averagedPosition: positionSource.averagedPosition
      averagedPositionCount: positionSource.averagedPositionCount
      overrideLocation: positionLocked ? positionSource.projectedPosition : undefined
    }

    /* Location marker reflecting the current GNSS position */
    LocationMarker {
      id: locationMarker
      mapSettings: mapCanvas.mapSettings
      anchors.fill: parent
      visible: positionSource.active && positionSource.positionInformation && positionSource.positionInformation.latitudeValid
      location: positionSource.projectedPosition
      device: positionSource.device
      accuracy: positionSource.projectedHorizontalAccuracy
      direction: positionSource.positionInformation
                 && positionSource.positionInformation.directionValid
                 ? positionSource.positionInformation.direction
                 : -1
      speed: positionSource.positionInformation
             && positionSource.positionInformation.speedValid
             ? positionSource.positionInformation.speed
             : -1

      onLocationChanged: {
        if ( gnssButton.followActive ) {
          gnssButton.followLocation(false);
        }
      }
    }

    /* Rubberband for vertices  */
    Item {
      // highlighting vertices
      VertexRubberband {
        id: vertexRubberband
        model: geometryEditingFeature.vertexModel
        mapSettings: mapCanvas.mapSettings
      }

      // highlighting geometry (point, line, surface)
      Rubberband {
        id: editingRubberband
        vertexModel: vertexModel
        mapSettings: mapCanvas.mapSettings
        width: 4
      }
    }

    /* Locator Highlight */
    GeometryHighlighter {
      id: locatorHighlightItem
    }

    /* Highlight the currently selected item on the feature list */
    FeatureListSelectionHighlight {
      id: featureListHighlight
      visible: !moveFeaturesToolbar.moveFeaturesRequested

      selectionModel: featureForm.selection
      mapSettings: mapCanvas.mapSettings

      color: "yellow"
      focusedColor: "#ff7777"
      selectedColor: Theme.mainColor
      width: 5
    }

    /* Highlight the currently selected item being moved */
    FeatureListSelectionHighlight {
      id: moveFeaturesHighlight
      visible: moveFeaturesToolbar.moveFeaturesRequested
      showSelectedOnly: true

      selectionModel: featureForm.selection
      mapSettings: mapCanvas.mapSettings
      translateX: mapToScreenTranslateX.screenDistance
      translateY: mapToScreenTranslateY.screenDistance

      color: "yellow"
      focusedColor: "#ff7777"
      selectedColor: Theme.mainColor
      width: 5
    }

    MapToScreen {
      id: mapToScreenTranslateX
      mapSettings: mapCanvas.mapSettings
      mapDistance: moveFeaturesToolbar.moveFeaturesRequested ? mapCanvas.mapSettings.center.x - moveFeaturesToolbar.startPoint.x : 0
    }
    MapToScreen {
      id: mapToScreenTranslateY
      mapSettings: mapCanvas.mapSettings
      mapDistance: moveFeaturesToolbar.moveFeaturesRequested ? mapCanvas.mapSettings.center.y - moveFeaturesToolbar.startPoint.y : 0
    }
  }

  Column {
    id: informationView
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    visible: navigation.isActive || positioningSettings.showPositionInformation

    width: parent.width

    NavigationInformationView {
      id: navigationInformationView
      visible: navigation.isActive
      navigation: navigation
    }

    PositionInformationView {
      id: positionInformationView
      visible: positioningSettings.showPositionInformation
      positionSource: positionSource
      antennaHeight: positioningSettings.antennaHeightActivated ? positioningSettings.antennaHeight : NaN
    }
  }

  DropShadow {
    anchors.fill: informationView
    visible: informationView.visible
    verticalOffset: -2
    radius: 6.0
    samples: 17
    color: "#30000000"
    source: informationView
  }

  /**************************************************
   * Map Canvas Decorations like
   * - Position Information View
   * - Scale Bar
   **************************************************/

  Text {
    id: coordinateLocatorInformationOverlay

    property bool coordinatesIsXY: !projectInfo.reprojectDisplayCoordinatesToWGS84
                                   && CoordinateReferenceSystemUtils.defaultCoordinateOrderForCrsIsXY(coordinateLocator.mapSettings.destinationCrs)
    property bool coordinatesIsGeographic: projectInfo.reprojectDisplayCoordinatesToWGS84
                                           || coordinateLocator.mapSettings.destinationCrs.isGeographic

    DistanceArea {
      id: digitizingGeometryMeasure

      property VectorLayer currentLayer: dashBoard.currentLayer

      rubberbandModel: currentRubberband ? currentRubberband.model : null
      project: qgisProject
      crs: qgisProject ? qgisProject.crs : CoordinateReferenceSystemUtils.invalidCrs()
    }

    // The position is dynamically calculated to follow the coordinate locator
    x: {
        var newX = coordinateLocator.displayPosition.x + 20;
        if (newX + width > mapCanvas.x + mapCanvas.width)
            newX -= width + 40;
        return newX;
    }
    y: {
        var newY = coordinateLocator.displayPosition.y + 10
        if (newY + height > mapCanvas.y + mapCanvas.height)
            newY -= height - 20;
        return newY;
    }

    text: {
      if ((qfieldSettings.numericalDigitizingInformation && stateMachine.state === "digitize" ) || stateMachine.state === 'measure') {
        var point = projectInfo.reprojectDisplayCoordinatesToWGS84
                    ? GeometryUtils.reprojectPointToWgs84(coordinateLocator.currentCoordinate, coordinateLocator.mapSettings.destinationCrs)
                    : coordinateLocator.currentCoordinate
        var coordinates;
        if (coordinatesIsXY) {
          coordinates = '<p>%1: %2<br>%3: %4</p>'
                        .arg(coordinatesIsGeographic ? qsTr( 'Lon' ) : 'X')
                        .arg(point.x.toLocaleString( Qt.locale(), 'f', coordinatesIsGeographic ? 5 : 2 ))
                        .arg(coordinatesIsGeographic ? qsTr( 'Lat' ) : 'Y')
                        .arg(point.y.toLocaleString( Qt.locale(), 'f', coordinatesIsGeographic ? 5 : 2 ));
        } else {
          coordinates = '<p>%1: %2<br>%3: %4</p>'
                        .arg(coordinatesIsGeographic ? qsTr( 'Lat' ) : 'Y')
                        .arg(point.y.toLocaleString( Qt.locale(), 'f', coordinatesIsGeographic ? 5 : 2 ))
                        .arg(coordinatesIsGeographic ? qsTr( 'Lon' ) : 'X')
                        .arg(point.x.toLocaleString( Qt.locale(), 'f', coordinatesIsGeographic ? 5 : 2 ));
        }

        return '%1%2%3%4%5'
                .arg(stateMachine.state === 'digitize' || !digitizingToolbar.isDigitizing
                     ? coordinates
                     : '')

                .arg(digitizingGeometryMeasure.lengthValid && digitizingGeometryMeasure.segmentLength != 0.0
                     && digitizingGeometryMeasure.segmentLength != digitizingGeometryMeasure.length
                     ? '<p>%1: %2</p>'
                       .arg( qsTr( 'Segment') )
                       .arg(UnitTypes.formatDistance( digitizingGeometryMeasure.segmentLength, 3, digitizingGeometryMeasure.lengthUnits ) )
                     : '')

                .arg(currentRubberband.model && currentRubberband.model.geometryType === QgsWkbTypes.PolygonGeometry
                     ? digitizingGeometryMeasure.perimeterValid
                       ? '<p>%1: %2</p>'
                         .arg( qsTr( 'Perimeter') )
                         .arg(UnitTypes.formatDistance( digitizingGeometryMeasure.perimeter, 3, digitizingGeometryMeasure.lengthUnits ) )
                       : ''
                     : digitizingGeometryMeasure.lengthValid
                     ? '<p>%1: %2</p>'
                       .arg( qsTr( 'Length') )
                       .arg(UnitTypes.formatDistance( digitizingGeometryMeasure.length, 3, digitizingGeometryMeasure.lengthUnits ) )
                     : '')

                .arg(digitizingGeometryMeasure.areaValid
                     ? '<p>%1: %2</p>'
                     .arg( qsTr( 'Area') )
                     .arg(UnitTypes.formatArea( digitizingGeometryMeasure.area, 3, digitizingGeometryMeasure.areaUnits ) )
                     : '')

                .arg(stateMachine.state === 'measure' && digitizingToolbar.isDigitizing
                     ? coordinates
                     : '')
      } else {
        return '';
      }
    }

    font: Theme.strongTipFont
    style: Text.Outline
    styleColor: Theme.light
  }

  ScaleBar {
    visible: qfieldSettings.showScaleBar
    mapSettings: mapCanvas.mapSettings

    anchors.left: mapCanvas.left
    anchors.bottom: mapCanvas.bottom
    anchors.margins: 10
  }

  DropShadow {
    anchors.fill: featureForm
    horizontalOffset: mainWindow.width >= mainWindow.height ? -2: 0
    verticalOffset: mainWindow.width < mainWindow.height ? -2: 0
    radius: 6.0
    samples: 17
    color: "#80000000"
    source: featureForm
  }

  QfToolButton {
    id: alertIcon
    iconSource: Theme.getThemeIcon( "ic_alert_black_24dp" )
    round: true
    bgcolor: "transparent"

    visible: messageLog.unreadMessages

    anchors.right: locatorItem.right
    anchors.top: locatorItem.top
    anchors.topMargin: 52

    onClicked: messageLog.visible = true
  }

  Column {
    id: zoomToolbar
    anchors.right: mapCanvas.right
    anchors.rightMargin: 4
    anchors.bottom: mapCanvas.bottom
    anchors.bottomMargin: ( mapCanvas.height - zoomToolbar.height / 2 ) / 2
    spacing: 4

    visible: locationToolbar.height / mapCanvas.height < 0.41

    QfToolButton {
      id: zoomInButton
      round: true
      anchors.right: parent.right

      bgcolor: Theme.darkGray
      iconSource: Theme.getThemeIcon( "ic_add_white_24dp" )

      transform: Scale {
          origin.x: zoomInButton.width / 1.5
          origin.y: zoomInButton.height / 1.25
          xScale: 0.75
          yScale: 0.75
      }

      onClicked: {
          if ( gnssButton.followActive ) gnssButton.followActiveSkipExtentChanged = true;
          mapCanvasMap.zoomIn(Qt.point(mapCanvas.x + mapCanvas.width / 2,mapCanvas.y + mapCanvas.height / 2));
      }
    }
    QfToolButton {
      id: zoomOutButton
      round: true
      anchors.right: parent.right

      bgcolor: Theme.darkGray
      iconSource: Theme.getThemeIcon( "ic_remove_white_24dp" )

      transform: Scale {
          origin.x: zoomOutButton.width / 1.5
          origin.y: zoomOutButton.height / 1.75
          xScale: 0.75
          yScale: 0.75
      }

      onClicked: {
          if ( gnssButton.followActive ) gnssButton.followActiveSkipExtentChanged = true;
          mapCanvasMap.zoomOut(Qt.point(mapCanvas.x + mapCanvas.width / 2,mapCanvas.y + mapCanvas.height / 2));
      }
    }
  }

  LocatorItem {
    id: locatorItem

    locatorModelSuperBridge.navigation: navigation
    locatorModelSuperBridge.bookmarks: bookmarkModel

    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 4

    visible: stateMachine.state !== 'measure'

    Keys.onReleased: {
      if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
        event.accepted = true
        state = "off"
      }
    }

    onStateChanged: {
      if ( state == "off" ) {
        focus = false
        if ( featureForm.visible ) {
          featureForm.focus = true
        } else {
          keyHandler.focus = true
        }
      }
    }
  }

  LocatorSettings {
      id: locatorSettings
      locatorModelSuperBridge: locatorItem.locatorModelSuperBridge

      modal: true
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
      parent: ApplicationWindow.overlay
  }

  DropShadow {
    anchors.fill: locatorItem
    visible: locatorItem.searchFieldVisible
    verticalOffset: 2
    radius: 10
    samples: 17
    color: "#66212121"
    source: locatorItem
  }

  DashBoard {
    id: dashBoard
    allowLayerChange: !digitizingToolbar.isDigitizing
    mapSettings: mapCanvas.mapSettings
    interactive: !welcomeScreen.visible
                 && !qfieldSettings.visible
                 && !qfieldCloudScreen.visible
                 && !qfieldLocalDataPickerScreen.visible

    onOpenedChanged: {
      if ( !opened ) {
        if ( featureForm.visible ) {
          featureForm.focus = true;
        }
      }
    }

    function ensureEditableLayerSelected() {
      var firstEditableLayer = null;
      var currentLayerLocked = false;
      for (var i = 0; i < layerTree.rowCount(); i++)
      {
        var index = layerTree.index(i, 0)
        if (firstEditableLayer === null)
        {
          if (
              layerTree.data(index,FlatLayerTreeModel.Type) === 'layer'
              && layerTree.data(index, FlatLayerTreeModel.ReadOnly) === false
              && layerTree.data(index, FlatLayerTreeModel.GeometryLocked) === false)
          {
             firstEditableLayer = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
          }
        }
        if (currentLayer != null && currentLayer === layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer))
        {
           if (
               layerTree.data(index, FlatLayerTreeModel.ReadOnly) === true
               || layerTree.data(index, FlatLayerTreeModel.GeometryLocked) === true
           )
           {
             currentLayerLocked = true;
           }
           else
           {
             break;
           }
        }
        if (
            firstEditableLayer !== null
            && (currentLayer == null || currentLayerLocked === true)
        )
        {
          currentLayer = firstEditableLayer;
          break;
        }
      }
    }
  }

  /* The main menu */
  Row {
    id: mainMenuBar
    width: childrenRect.width + 8
    height: childrenRect.height + 8
    topPadding: 4
    leftPadding: 4
    spacing: 4

    QfToolButton {
      id: menuButton
      round: true
      iconSource: Theme.getThemeIcon( "ic_menu_white_24dp" )
      bgcolor: dashBoard.opened ? Theme.mainColor : Theme.darkGray

      onClicked: dashBoard.opened ? dashBoard.close() : dashBoard.open()

      onPressAndHold: {
        mainMenu.popup(menuButton.x, menuButton.y)
      }
    }

    CloseTool {
      id: closeMeasureTool
      visible: stateMachine.state === 'measure'
      toolText: qsTr( 'Close measure tool' )
      onClosedTool: mainWindow.closeMeasureTool()
    }

    CloseTool {
      id: closeGeometryEditorsTool
      visible: ( stateMachine.state === "digitize" && vertexModel.vertexCount > 0 )
      toolText: qsTr( 'Stop editing' )
      onClosedTool: geometryEditorsToolbar.cancelEditors()
    }

    CloseTool {
      id: abortRequestGeometry
      visible: digitizingToolbar.geometryRequested
      toolText: qsTr( 'Cancel addition' )
      onClosedTool: digitizingToolbar.cancel()
    }
  }

  Column {
    id: mainToolbar
    anchors.left: mainMenuBar.left
    anchors.top: mainMenuBar.bottom
    anchors.leftMargin: 4
    spacing: 4

    QfToolButton {
      id: topologyButton
      round: true
      visible: stateMachine.state === "digitize"
          && dashBoard.currentLayer
          && dashBoard.currentLayer.isValid
          && ( dashBoard.currentLayer.geometryType() === QgsWkbTypes.PolygonGeometry || dashBoard.currentLayer.geometryType() === QgsWkbTypes.LineGeometry )
      state: qgisProject && qgisProject.topologicalEditing ? "On" : "Off"
      iconSource: Theme.getThemeIcon( "ic_topology_white_24dp" )

      bgcolor: Theme.darkGray

      states: [
        State {

          name: "Off"
          PropertyChanges {
            target: topologyButton
            iconSource: Theme.getThemeIcon( "ic_topology_white_24dp" )
            bgcolor: Qt.hsla(Theme.darkGray.hslHue, Theme.darkGray.hslSaturation, Theme.darkGray.hslLightness, 0.3)
          }
        },

        State {
          name: "On"
          PropertyChanges {
            target: topologyButton
            iconSource: Theme.getThemeIcon( "ic_topology_green_24dp" )
            bgcolor: Theme.darkGray
          }
        }
      ]

      onClicked: {
        qgisProject.topologicalEditing = !qgisProject.topologicalEditing;
        displayToast( qgisProject.topologicalEditing ? qsTr( "Topological editing turned on" ) : qsTr( "Topological editing turned off" ) );
      }
    }

    QfToolButton {
      id: freehandButton
      round: true
      visible: hoverHandler.hovered && !gnssLockButton.linkActive && stateMachine.state === "digitize"
               && ((digitizingToolbar.geometryRequested && digitizingToolbar.geometryRequestedLayer && digitizingToolbar.geometryRequestedLayer.isValid &&
                   (digitizingToolbar.geometryRequestedLayer.geometryType() === QgsWkbTypes.PolygonGeometry
                    || digitizingToolbar.geometryRequestedLayer.geometryType() === QgsWkbTypes.LineGeometry))
                   || (!digitizingToolbar.geometryRequested && dashBoard.currentLayer && dashBoard.currentLayer.isValid &&
                   (dashBoard.currentLayer.geometryType() === QgsWkbTypes.PolygonGeometry
                    || dashBoard.currentLayer.geometryType() === QgsWkbTypes.LineGeometry)))
      iconSource: Theme.getThemeIcon( "ic_freehand_white_24dp" )

      bgcolor: Theme.darkGray

      property bool freehandDigitizing: false
      state: freehandDigitizing ? "On" : "Off"

      states: [
        State {
          name: "Off"
          PropertyChanges {
            target: freehandButton
            iconSource: Theme.getThemeIcon( "ic_freehand_white_24dp" )
            bgcolor: Qt.hsla(Theme.darkGray.hslHue, Theme.darkGray.hslSaturation, Theme.darkGray.hslLightness, 0.3)
          }
        },

        State {
          name: "On"
          PropertyChanges {
            target: freehandButton
            iconSource: Theme.getThemeIcon( "ic_freehand_green_24dp" )
            bgcolor: Theme.darkGray
          }
        }
      ]

      onClicked: {
        freehandDigitizing = !freehandDigitizing

        if (freehandDigitizing && positioningSettings.positioningCoordinateLock) {
          positioningSettings.positioningCoordinateLock = false;
        }

        displayToast( freehandDigitizing ? qsTr( "Freehand digitizing turned on" ) : qsTr( "Freehand digitizing turned off" ) );
        settings.setValue( "/QField/Digitizing/FreehandActive", freehandDigitizing );
      }

      Component.onCompleted: {
        freehandDigitizing = settings.valueBool( "/QField/Digitizing/FreehandActive", false )
      }
    }
  }

  Column {
    id: locationToolbar
    anchors.right: mapCanvas.right
    anchors.rightMargin: 4
    anchors.bottom: mapCanvas.bottom
    anchors.bottomMargin: 4
    spacing: 4

    QfToolButton {
      id: navigationButton
      visible: navigation.isActive
      round: true
      anchors.right: parent.right

      property bool isFollowLocationActive: positionSource.active && gnssButton.followActive && followIncludeDestination
      iconSource: isFollowLocationActive
                  ? Theme.getThemeIcon( "ic_navigation_flag_white_24dp" )
                  : Theme.getThemeIcon( "ic_navigation_flag_purple_24dp" )
      bgcolor: isFollowLocationActive
               ? Theme.navigationColor
               : Theme.darkGray

      /*
      / When set to true, when the map follows the device's current position, the extent
      / will always include the destination marker.
      */
      property bool followIncludeDestination: true

      onClicked: {
        if (positionSource.active && gnssButton.followActive) {
          followIncludeDestination = !followIncludeDestination
          settings.setValue("/QField/Navigation/FollowIncludeDestination", followIncludeDestination);

          gnssButton.followLocation(true)
        } else {
          mapCanvas.mapSettings.setCenter(navigation.destination)
        }
      }

      onPressAndHold: {
        navigationMenu.popup(
          locationToolbar.x + locationToolbar.width - navigationMenu.width,
          locationToolbar.y + locationToolbar.height - navigationMenu.height
        )
      }

      Component.onCompleted: {
        followIncludeDestination = settings.valueBool("/QField/Navigation/FollowIncludeDestination", true)
      }
    }

    QfToolButton {
      id: gnssLockButton
      anchors.right: parent.right
      state: positionSource.active && positioningSettings.positioningCoordinateLock ? "On" : "Off"
      visible: gnssButton.state === "On" && ( stateMachine.state === "digitize" || stateMachine.state === 'measure' )
      round: true
      checkable: true
      checked: positioningSettings.positioningCoordinateLock

      states: [
        State {
          name: "Off"
          PropertyChanges {
            target: gnssLockButton
            iconSource: Theme.getThemeIcon( "ic_gps_link_white_24dp" )
            bgcolor: Theme.darkGraySemiOpaque
          }
        },

        State {
          name: "On"
          PropertyChanges {
            target: gnssLockButton
            iconSource: Theme.getThemeIcon( "ic_gps_link_activated_white_24dp" )
            bgcolor: Theme.darkGray
          }
        }
      ]

      onCheckedChanged: {
        if (gnssButton.state === "On") {
          if (checked) {
              if (freehandButton.freehandDigitizing) {
                  // deactivate freehand digitizing when cursor locked is on
                  freehandButton.clicked();
              }
              displayToast( qsTr( "Coordinate cursor now locked to position" ) )
              if (positionSource.positionInformation.latitudeValid) {
                var screenLocation = mapCanvas.mapSettings.coordinateToScreen(locationMarker.location);
                if ( screenLocation.x < 0 || screenLocation.x > mainWindow.width ||
                     screenLocation.y < 0 || screenLocation.y > mainWindow.height ) {
                  mapCanvas.mapSettings.setCenter(positionSource.projectedPosition);
                }
              }
              positioningSettings.positioningCoordinateLock = true;
          } else {
            displayToast( qsTr( "Coordinate cursor unlocked" ) )
            positioningSettings.positioningCoordinateLock = false;
            // deactivate any active averaged position collection
            positionSource.averagedPosition = false;
          }
        }
      }
    }

    QfToolButton {
      id: gnssButton
      state: positionSource.active ? "On" : "Off"
      visible: positionSource.valid
      round: true

      anchors.right: parent.right

      onIconSourceChanged: {
        if( state === "On" ){
          if( positionSource.positionInformation && positionSource.positionInformation.latitudeValid ) {
            displayToast( qsTr( "Received position" ) )
          } else {
            displayToast( qsTr( "Searching for position" ) )
          }
        }
      }

      /*
      / When set to true, the map will follow the device's current position; the map
      / will stop following the position whe the user manually drag the map.
      */
      property bool followActive: false
      /*
      / When set to true, map canvas extent changes will not result in the
      / deactivation of the above followActive mode.
      */
      property bool followActiveSkipExtentChanged: false

      states: [
        State {
          name: "Off"
          PropertyChanges {
            target: gnssButton
            iconSource: Theme.getThemeIcon( "ic_location_disabled_white_24dp" )
            bgcolor: Theme.darkGraySemiOpaque
          }
        },

        State {
          name: "On"
          PropertyChanges {
            target: gnssButton
            iconSource: positionSource.positionInformation && positionSource.positionInformation.latitudeValid ? Theme.getThemeIcon( "ic_my_location_" + ( followActive ? "white" : "blue" ) + "_24dp" ) : Theme.getThemeIcon( "ic_gps_not_fixed_white_24dp" )
            bgcolor: followActive ? Theme.positionColor : Theme.darkGray
          }
        }
      ]

      onClicked: {
        followActive = true
        if ( positionSource.projectedPosition.x )
        {
          if ( !positionSource.active )
          {
            positioningSettings.positioningActivated = true
          }
          else
          {
              followLocation(true);
              displayToast( qsTr( "Canvas follows location" ) )
          }
        }
        else
        {
          if ( positionSource.valid )
          {
            if ( positionSource.active )
            {
              displayToast( qsTr( "Waiting for location" ) )
            }
            else
            {
              positioningSettings.positioningActivated = true
            }
          }
        }
      }

      onPressAndHold: {
        gnssMenu.popup(locationToolbar.x + locationToolbar.width - gnssMenu.width, locationToolbar.y + locationToolbar.height - gnssMenu.height)
      }

      property int followLocationMaxScale: 10
      property int followLocationMinMargin: 40
      property int followLocationScreenFraction: settings ? settings.value( "/QField/Positioning/FollowScreenFraction", 5 ) : 5
      function followLocation(forceRecenter) {
        var screenLocation = mapCanvas.mapSettings.coordinateToScreen(positionSource.projectedPosition);
        if (navigation.isActive && navigationButton.followIncludeDestination) {
          if (mapCanvas.mapSettings.scale > followLocationMaxScale) {
            var screenDestination = mapCanvas.mapSettings.coordinateToScreen(navigation.destination);
            if (forceRecenter
                || screenDestination.x < followLocationMinMargin
                || screenDestination.x > (mainWindow.width - followLocationMinMargin)
                || screenDestination.y < followLocationMinMargin
                || screenDestination.y > (mainWindow.height - followLocationMinMargin)
                || screenLocation.x < followLocationMinMargin
                || screenLocation.x > (mainWindow.width - followLocationMinMargin)
                || screenLocation.y < followLocationMinMargin
                || screenLocation.y > (mainWindow.height - followLocationMinMargin)
                || (Math.abs(screenDestination.x - screenLocation.x) < mainWindow.width / 3
                    && Math.abs(screenDestination.y - screenLocation.y) < mainWindow.height / 3)) {
              gnssButton.followActiveSkipExtentChanged = true;
              var points = [positionSource.projectedPosition, navigation.destination];
              mapCanvas.mapSettings.setExtentFromPoints(points)
            }
          }
        } else {
          var threshold = Math.min( mainWindow.width, mainWindow.height ) / followLocationScreenFraction;
          if ( forceRecenter
               || screenLocation.x < threshold
               || screenLocation.x > mainWindow.width - threshold
               || screenLocation.y < threshold
               || screenLocation.y > mainWindow.height - threshold )
          {
            gnssButton.followActiveSkipExtentChanged = true;
            mapCanvas.mapSettings.setCenter(positionSource.projectedPosition);
          }
        }
      }

      Rectangle {
          anchors {
              top: parent.top
              right: parent.right
              rightMargin: 2
              topMargin: 2
          }

          width: 12
          height: 12
          radius: width / 2

          border.width: 1.5
          border.color: 'white'

          visible: positioningSettings.accuracyIndicator && gnssButton.state === "On"
          color: !positionSource.positionInformation
                 || !positionSource.positionInformation.haccValid
                 || positionSource.positionInformation.hacc > positioningSettings.accuracyBad
                     ? Theme.accuracyBad
                     : positionSource.positionInformation.hacc > positioningSettings.accuracyExcellent
                       ? Theme.accuracyTolerated
                       : Theme.accuracyExcellent
      }
    }

    Connections {
        target: mapCanvas.mapSettings

        function onExtentChanged() {
            if ( gnssButton.followActive ) {
                if ( gnssButton.followActiveSkipExtentChanged ) {
                    gnssButton.followActiveSkipExtentChanged = false;
                } else {
                    gnssButton.followActive = false
                    displayToast( qsTr( "Canvas stopped following location" ) )
                }
            }
        }
    }

    DigitizingToolbar {
      id: digitizingToolbar

      stateVisible: (stateMachine.state === "digitize"
                     && dashBoard.currentLayer
                     && !dashBoard.currentLayer.readOnly
                     // unfortunately there is no way to call QVariant::toBool in QML so the value is a string
                     && dashBoard.currentLayer.customProperty( 'QFieldSync/is_geometry_locked' ) !== 'true'
                     && !geometryEditorsToolbar.stateVisible
                     && !moveFeaturesToolbar.stateVisible
                     && (projectInfo.editRights || projectInfo.insertRights))
                    || stateMachine.state === 'measure'
                    || (stateMachine.state === "digitize" && digitizingToolbar.geometryRequested)
      rubberbandModel: currentRubberband ? currentRubberband.model : null
      mapSettings: mapCanvas.mapSettings
      showConfirmButton: stateMachine.state === "digitize"
      screenHovering: hoverHandler.hovered

      digitizingLogger.type: stateMachine.state === 'measure' ? '' : 'add'

      FeatureModel {
        id: digitizingFeature
        project: qgisProject
        currentLayer: digitizingToolbar.geometryRequested ? digitizingToolbar.geometryRequestedLayer : dashBoard.currentLayer
        positionInformation: positionSource.positionInformation
        topSnappingResult: coordinateLocator.topSnappingResult
        positionLocked: positionSource.active && positioningSettings.positioningCoordinateLock
        cloudUserInformation: cloudConnection.userInformation
        geometry: Geometry {
          id: digitizingGeometry
          rubberbandModel: digitizingRubberband.model
          vectorLayer: digitizingToolbar.geometryRequested ? digitizingToolbar.geometryRequestedLayer : dashBoard.currentLayer
        }
      }

      property string previousStateMachineState: ''
      onGeometryRequestedChanged: {
          if ( geometryRequested ) {
              digitizingRubberband.model.reset()
              previousStateMachineState = stateMachine.state
              stateMachine.state = "digitize"
          }
          else
          {
              stateMachine.state = previousStateMachineState
          }
      }

      onVertexCountChanged: {
        if( qfieldSettings.autoSave && stateMachine.state === "digitize" ) {
            if( digitizingToolbar.geometryValid )
            {
                if (digitizingRubberband.model.geometryType === QgsWkbTypes.NullGeometry )
                {
                  digitizingRubberband.model.reset()
                }
                else
                {
                  digitizingFeature.geometry.applyRubberband()
                  digitizingFeature.applyGeometry()
                }

                if( !overlayFeatureFormDrawer.featureForm.featureCreated )
                {
                    overlayFeatureFormDrawer.featureModel.geometry = digitizingFeature.geometry
                    overlayFeatureFormDrawer.featureModel.applyGeometry()
                    overlayFeatureFormDrawer.featureForm.resetAttributes()
                    if( overlayFeatureFormDrawer.featureForm.model.constraintsHardValid ) {
                      // when the constrainst are fulfilled
                      // indirect action, no need to check for success and display a toast, the log is enough
                      overlayFeatureFormDrawer.featureForm.featureCreated = overlayFeatureFormDrawer.featureForm.create()
                    }
                } else {
                  // indirect action, no need to check for success and display a toast, the log is enough
                  overlayFeatureFormDrawer.featureModel.geometry = digitizingFeature.geometry
                  overlayFeatureFormDrawer.featureModel.applyGeometry()
                  overlayFeatureFormDrawer.featureForm.save()
                }
            } else {
              if( overlayFeatureFormDrawer.featureForm.featureCreated ) {
                // delete the feature when the geometry gets invalid again
                // indirect action, no need to check for success and display a toast, the log is enough
                overlayFeatureFormDrawer.featureForm.featureCreated = !overlayFeatureFormDrawer.featureForm.deleteFeature()
              }
            }
        }
      }

      onCancel: {
          if ( geometryRequested )
          {
              geometryRequested = false
          }
      }

      onConfirmed: {
        if ( geometryRequested )
        {
            if ( overlayFeatureFormDrawer.isAdding )
                overlayFeatureFormDrawer.open()

            coordinateLocator.flash()
            digitizingFeature.geometry.applyRubberband()
            geometryRequestedItem.requestedGeometry(digitizingFeature.geometry)
            digitizingRubberband.model.reset()
            geometryRequested = false
            return;
        }

        if (digitizingRubberband.model.geometryType === QgsWkbTypes.NullGeometry )
        {
          digitizingRubberband.model.reset()
        }
        else
        {
          coordinateLocator.flash()
          digitizingFeature.geometry.applyRubberband()
          digitizingFeature.applyGeometry()
          digitizingRubberband.model.frozen = true
          digitizingFeature.updateRubberband()
        }

        if ( !digitizingFeature.suppressFeatureForm() )
        {
          overlayFeatureFormDrawer.featureModel.geometry = digitizingFeature.geometry
          overlayFeatureFormDrawer.featureModel.applyGeometry()
          overlayFeatureFormDrawer.featureModel.resetAttributes()
          overlayFeatureFormDrawer.open()
          overlayFeatureFormDrawer.state = "Add"
          overlayFeatureFormDrawer.featureForm.reset()
        }
        else
        {
          if ( !overlayFeatureFormDrawer.featureForm.featureCreated ) {
              overlayFeatureFormDrawer.featureModel.geometry = digitizingFeature.geometry
              overlayFeatureFormDrawer.featureModel.applyGeometry()
              overlayFeatureFormDrawer.featureModel.resetAttributes()
              if ( !overlayFeatureFormDrawer.featureModel.create() ) {
                displayToast( qsTr( "Failed to create feature!" ), 'error' )
              }
          } else {
              if ( !overlayFeatureFormDrawer.featureModel.save() ) {
                displayToast( qsTr( "Failed to save feature!" ), 'error' )
              }
          }
          digitizingRubberband.model.reset()
          digitizingFeature.resetFeature();
        }
      }
    }

    GeometryEditorsToolbar {
      id: geometryEditorsToolbar

      featureModel: geometryEditingFeature
      mapSettings: mapCanvas.mapSettings
      editorRubberbandModel: geometryEditorsRubberband.model
      screenHovering: hoverHandler.hovered

      stateVisible: ( stateMachine.state === "digitize" && vertexModel.vertexCount > 0 )
    }

    ConfirmationToolbar {
        id: moveFeaturesToolbar

        property bool moveFeaturesRequested: false
        property variant startPoint: undefined // QgsPoint or undefined
        property variant endPoint: undefined // QgsPoint or undefined
        signal moveConfirmed
        signal moveCanceled

        stateVisible: moveFeaturesRequested

        onConfirm: {
            endPoint = mapCanvas.mapSettings.center
            moveFeaturesRequested = false
            moveConfirmed()
        }
        onCancel: {
            startPoint = undefined
            endPoint = undefined
            moveFeaturesRequested = false
            moveCanceled()
        }

        function initializeMoveFeatures() {
            if ( featureForm  && featureForm.selection.model.selectedCount === 1 ) {
              featureForm.extentController.zoomToSelected()
            }

            startPoint = mapCanvas.mapSettings.center
            moveFeaturesRequested = true
        }
    }
  }

  BookmarkProperties {
    id: bookmarkProperties
  }

  Menu {
    id: mainMenu
    title: qsTr( "Main Menu" )

    width: {
        var result = 0;
        var padding = 0;
        for (var i = 0; i < count; ++i) {
            var item = itemAt(i);
            result = Math.max(item.contentItem.implicitWidth, result);
            padding = Math.max(item.padding, padding);
        }
        return result + padding * 2;
    }

    MenuItem {
      text: qsTr( 'Measure Tool' )

      font: Theme.defaultFont
      height: 48
      leftPadding: 10

      onTriggered: {
        dashBoard.close()
        changeMode( 'measure' )
        highlighted = false
      }
    }

    MenuItem {
      id: printItem
      text: qsTr( "Print to PDF" )

      font: Theme.defaultFont
      height: 48
      leftPadding: 10

      onTriggered: {
        if (layoutListInstantiator.model.rowCount() > 1)
        {
          printMenu.popup( mainMenu.x, mainMenu.y + printItem.y )
        }
        else
        {
          mainMenu.close();
          displayToast( qsTr( 'Printing to PDF') )
          printMenu.printName =layoutListInstantiator.model.titleAt( 0 );
          printMenu.printTimer.restart();
        }
        highlighted = false
      }
    }

    MenuSeparator { width: parent.width }

    MenuItem {
      id: openProjectMenuItem

      font: Theme.defaultFont
      height: 48
      leftPadding: 10

      text: qsTr( "Go to Home Screen" )
      onTriggered: {
        dashBoard.close()
        welcomeScreen.visible = true
        welcomeScreen.focus = true
        highlighted = false
      }
    }

    MenuItem {
      id: openProjectFolderMenuItem

      font: Theme.defaultFont
      height: 48
      leftPadding: 10

      text: qsTr( "Open Project Folder" )
      onTriggered: {
        dashBoard.close()
        qfieldLocalDataPickerScreen.projectFolderView = true
        qfieldLocalDataPickerScreen.model.resetToPath(projectInfo.filePath)
        qfieldLocalDataPickerScreen.visible = true
      }
    }

    MenuSeparator { width: parent.width }

    MenuItem {
      text: qsTr( "Settings" )

      font: Theme.defaultFont
      height: 48
      leftPadding: 10

      onTriggered: {
        dashBoard.close()
        qfieldSettings.visible = true
        highlighted = false
      }
    }

    MenuItem {
      text: qsTr( "Message Log" )

      font: Theme.defaultFont
      height: 48
      leftPadding: 10

      onTriggered: {
        dashBoard.close()
        messageLog.visible = true
        highlighted = false
      }
    }

    MenuItem {
      text: qsTr( "About QField" )

      font: Theme.defaultFont
      height: 48
      leftPadding: 10

      onTriggered: {
        dashBoard.close()
        aboutDialog.visible = true
        highlighted = false
      }
    }

    Connections {
        target: printMenu

        function onEnablePrintItem(rows) {
          printItem.enabled = rows
        }
    }

    /*
    We removed this MenuItem part, because usually a mobile app has not the functionality to quit.
    But we keep the code in case, the concept changes or we need to close the app completely (remove from background)
    */

    /*
    Controls.MenuSeparator {}

    Controls.MenuItem {
      text: qsTr( "Quit" )
      iconSource: Theme.getThemeIcon( "ic_close_white_24dp" )
      onTriggered: {
        Qt.quit()
      }
    }
    */
  }

  Menu {
    id: printMenu

    property alias printTimer: timer
    property alias printName: timer.printName

    title: qsTr( "Print to PDF" )

    signal enablePrintItem( int rows )

    width: {
        var result = 0;
        var padding = 0;
        for (var i = 0; i < count; ++i) {
            var item = itemAt(i);
            result = Math.max(item.contentItem.implicitWidth, result);
            padding = Math.max(item.padding, padding);
        }
        return Math.min( result + padding * 2,mainWindow.width - 20);
    }

    MenuItem {
      text: qsTr( 'Select template below' )

      font: Theme.defaultFont
      height: 48
      leftPadding: 10

      enabled: false
    }

    Instantiator {

      id: layoutListInstantiator

      model: PrintLayoutListModel {
      }

      MenuItem {
        text: Title

        font: Theme.defaultFont
        leftPadding: 10

        onTriggered: {
            highlighted = false
            displayToast( qsTr( 'Printing to PDF') )
            printMenu.printName = Title
            printMenu.printTimer.restart();
        }
      }
      onObjectAdded: printMenu.insertItem(index+1, object)
      onObjectRemoved: printMenu.removeItem(object)
    }

    Timer {
      id: timer

      property string printName: ''

      interval: 500
      repeat: false
      onTriggered: iface.print( printName )
    }
  }

  PositioningSettings {
    id: positioningSettings

    onPositioningActivatedChanged: {
      if ( positioningActivated ) {
        if ( platformUtilities.checkPositioningPermissions() ) {
          displayToast( qsTr( "Activating positioning service" ) )
          positionSource.active = true
        } else {
          displayToast( qsTr( "QField has no permissions to use positioning." ), 'warning' )
          positioningSettings.positioningActivated = false
        }
      } else {
          positionSource.active = false
      }
    }
  }

  Menu {
    id: canvasMenu
    title: qsTr( "Map Canvas Options" )
    font: Theme.defaultFont

    property var point
    onPointChanged: {
      var displayPoint = projectInfo.reprojectDisplayCoordinatesToWGS84
                         ? GeometryUtils.reprojectPointToWgs84(canvasMenu.point, mapCanvas.mapSettings.destinationCrs)
                         : canvasMenu.point
      var isXY = !projectInfo.reprojectDisplayCoordinatesToWGS84
                 && CoordinateReferenceSystemUtils.defaultCoordinateOrderForCrsIsXY(mapCanvas.mapSettings.destinationCrs);
      var isGeographic = projectInfo.reprojectDisplayCoordinatesToWGS84
                         || mapCanvas.mapSettings.destinationCrs.isGeographic

      var xLabel = isGeographic ? qsTr( 'Lon' ) : 'X';
      var xValue = Number( displayPoint.x ).toLocaleString( Qt.locale(), 'f', isGeographic ? 7 : 3 )
      var yLabel = isGeographic ? qsTr( 'Lat' ) : 'Y'
      var yValue = Number( displayPoint.y ).toLocaleString( Qt.locale(), 'f', isGeographic ? 7 : 3 )
      xItem.text = isXY
                   ? xLabel + ': ' + xValue
                   : yLabel + ': ' + yValue
      yItem.text = isXY
                   ? yLabel + ': ' + yValue
                   : xLabel + ': ' + xValue
    }

    width: {
        var result = 0;
        var padding = 0;
        for (var i = 0; i < count; ++i) {
            var item = itemAt(i);
            result = Math.max(item.contentItem.implicitWidth, result);
            padding = Math.max(item.padding, padding);
        }
        return Math.min( result + padding * 2,mainWindow.width - 20);
    }

    MenuItem {
        id: xItem
        text: ""
        height: 48
        font: Theme.defaultFont
        enabled:false
    }

    MenuItem {
        id: yItem
        text: ""
        height: 48
        font: Theme.defaultFont
        enabled:false
    }

    MenuSeparator { width: parent.width }

    MenuItem {
      id: addBookmarkItem
      text: qsTr( "Add Bookmark" )
      icon.source: Theme.getThemeIcon( "ic_bookmark_black_24dp" )
      height: 48
      leftPadding: 10
      font: Theme.defaultFont

      onTriggered: {
        var name = qsTr('Untitled bookmark');
        var group = ''
        var id = bookmarkModel.addBookmarkAtPoint(canvasMenu.point, name, group);
        if (id !== '') {
          bookmarkProperties.bookmarkId = id;
          bookmarkProperties.bookmarkName = name;
          bookmarkProperties.bookmarkGroup = group;
          bookmarkProperties.open();
        }
      }
    }

    MenuItem {
      id: setDestinationItem
      text: qsTr( "Set as Destination" )
      icon.source: Theme.getThemeIcon( "ic_navigation_flag_purple_24dp" )
      height: 48
      leftPadding: 10
      font: Theme.defaultFont

      onTriggered: {
        navigation.destination = canvasMenu.point
      }
    }

    MenuItem {
      id: copyCoordinatesItem
      text: qsTr( "Copy Coordinates" )
      height: 48
      leftPadding: 50
      font: Theme.defaultFont

      onTriggered: {
        var displayPoint = projectInfo.reprojectDisplayCoordinatesToWGS84
                           ? GeometryUtils.reprojectPointToWgs84(canvasMenu.point, mapCanvas.mapSettings.destinationCrs)
                           : canvasMenu.point
        platformUtilities.copyTextToClipboard(StringUtils.pointInformation(displayPoint,
                                                                           projectInfo.reprojectDisplayCoordinatesToWGS84
                                                                           ? CoordinateReferenceSystemUtils.wgs84Crs()
                                                                           : mapCanvas.mapSettings.destinationCrs))
        displayToast(qsTr('Coordinates copied to clipboard'));
      }
    }
  }

  Menu {
    id: navigationMenu
    title: qsTr( "Navigation Options" )
    font: Theme.defaultFont

    width: {
        var result = 0;
        var padding = 0;
        for (var i = 0; i < count; ++i) {
            var item = itemAt(i);
            result = Math.max(item.contentItem.implicitWidth, result);
            padding = Math.max(item.padding, padding);
        }
        return Math.min( result + padding * 2,mainWindow.width - 20);
    }

    MenuItem {
      id: cancelNavigationItem
      text: qsTr( "Clear Destination" )
      height: 48
      font: Theme.defaultFont

      onTriggered: {
        navigation.clear();
      }
    }
  }

  Menu {
    id: gnssMenu
    title: qsTr( "Positioning Options" )
    font: Theme.defaultFont

    width: {
        var result = 0;
        var padding = 0;
        for (var i = 0; i < count; ++i) {
            var item = itemAt(i);
            result = Math.max(item.contentItem.implicitWidth, result);
            padding = Math.max(item.padding, padding);
        }
        return Math.min( result + padding * 2,mainWindow.width - 20);
    }

    MenuItem {
        id: positioningDeviceName
        text: positioningSettings.positioningDeviceName
        height: 48
        font: Theme.defaultFont
        enabled:false
    }

    MenuSeparator { width: parent.width }

    MenuItem {
      id: positioningItem
      text: qsTr( "Enable Positioning" )
      height: 48
      leftPadding: 15
      font: Theme.defaultFont

      checkable: true
      checked: positioningSettings.positioningActivated
      indicator.height: 20
      indicator.width: 20
      indicator.implicitHeight: 24
      indicator.implicitWidth: 24
      onCheckedChanged: positioningSettings.positioningActivated = checked
    }

    MenuItem {
      text: qsTr( "Show Position Information" )
      height: 48
      leftPadding: 15
      font: Theme.defaultFont

      checkable: true
      checked: positioningSettings.showPositionInformation
      indicator.height: 20
      indicator.width: 20
      indicator.implicitHeight: 24
      indicator.implicitWidth: 24
      onCheckedChanged: positioningSettings.showPositionInformation = checked
    }

    MenuItem {
      text: qsTr( "Positioning Settings" )
      height: 48
      leftPadding: 50
      font: Theme.defaultFont

      onTriggered: {
        qfieldSettings.currentPanel = 1
        qfieldSettings.visible = true
      }
    }

    MenuSeparator { width: parent.width }

    MenuItem {
      text: qsTr( "Center to Location" )
      height: 48
      leftPadding: 50
      font: Theme.defaultFont

      onTriggered: {
        mapCanvas.mapSettings.setCenter(positionSource.projectedPosition)
      }
    }

    MenuItem {
      text: qsTr( "Add Bookmark at Location" )
      icon.source: Theme.getThemeIcon( "ic_bookmark_black_24dp" )
      height: 48
      leftPadding: 10
      font: Theme.defaultFont

      onTriggered: {
        if (!positioningSettings.positioningActivated || positionSource.positionInformation === undefined || !positionSource.positionInformation.latitudeValid) {
          displayToast(qsTr('Current location unknown'));
          return;
        }

        var name = qsTr('My location') + ' (' + new Date().toLocaleString() + ')';
        var group = 'blue';
        var id = bookmarkModel.addBookmarkAtPoint(positionSource.projectedPosition, name, group)
        if (id !== '') {
          bookmarkProperties.bookmarkId = id;
          bookmarkProperties.bookmarkName = name;
          bookmarkProperties.bookmarkGroup = group;
          bookmarkProperties.open();
        }
      }
    }

    MenuItem {
      text: qsTr( "Copy Location Coordinates" )
      height: 48
      leftPadding: 50
      font: Theme.defaultFont

      onTriggered: {
        if (!positioningSettings.positioningActivated || positionSource.positionInformation === undefined || !positionSource.positionInformation.latitudeValid) {
          displayToast(qsTr('Current location unknown'));
          return;
        }

        var coordinates = projectInfo.reprojectDisplayCoordinatesToWGS84
                          ? StringUtils.pointInformation(positionSource.sourcePosition, CoordinateReferenceSystemUtils.wgs84Crs())
                          : StringUtils.pointInformation(positionSource.projectedPosition, mapCanvas.mapSettings.destinationCrs)
        coordinates += ' ('+ qsTr('Accuracy') + ' ' +
                       ( positionSource.positionInformation && positionSource.positionInformation.haccValid
                         ? positionSource.positionInformation.hacc.toLocaleString(Qt.locale(), 'f', 3) + " m"
                         : qsTr( "N/A" ) ) + ')';

        platformUtilities.copyTextToClipboard(coordinates)
        displayToast(qsTr('Current location copied to clipboard'));
      }
    }
  }

  /* The feature form */
  FeatureListForm {
    id: featureForm

    objectName: "featureForm"
    mapSettings: mapCanvas.mapSettings
    digitizingToolbar: digitizingToolbar
    moveFeaturesToolbar: moveFeaturesToolbar

    visible: state != "Hidden"
    focus: visible

    anchors { right: parent.right; bottom: parent.bottom }
    border { color: "lightGray"; width: 1 }
    allowEdit: stateMachine.state === "digitize"
    allowDelete: stateMachine.state === "digitize"

    model: MultiFeatureListModel {}

    selection: FeatureListModelSelection {
      id: featureListModelSelection
      model: featureForm.model
    }

    selectionColor: "#ff7777"

    onShowMessage: displayToast(message)

    onEditGeometry: {
      // Set overall selected (i.e. current) layer to that of the feature geometry being edited,
      // important for snapping settings to make sense when set to current layer
      if ( dashBoard.currentLayer != featureForm.selection.focusedLayer ) {
        dashBoard.currentLayer = featureForm.selection.focusedLayer
        displayToast( qsTr( "Current layer switched to the one holding the selected geometry." ) );
      }
      geometryEditingFeature.vertexModel.geometry = featureForm.selection.focusedGeometry
      geometryEditingFeature.vertexModel.crs = featureForm.selection.focusedLayer.crs
      geometryEditingFeature.currentLayer = featureForm.selection.focusedLayer
      geometryEditingFeature.feature = featureForm.selection.focusedFeature

      if (!vertexModel.editingAllowed)
      {
        displayToast( qsTr( "Editing of multi geometry layer is not supported yet." ) )
        vertexModel.clear()
      }
      else
      {
        featureForm.state = "Hidden"
      }

      geometryEditorsToolbar.init()
    }

    Component.onCompleted: focusstack.addFocusTaker( this )

    //that the focus is set by selecting the empty space
    MouseArea {
      anchors.fill: parent
      propagateComposedEvents: true
      enabled: !parent.activeFocus

      //onPressed because onClicked shall be handled in underlying MouseArea
      onPressed: {
        parent.focus=true
        mouse.accepted=false
      }
    }
  }

  OverlayFeatureFormDrawer {
    id: overlayFeatureFormDrawer
    digitizingToolbar: digitizingToolbar
    featureModel.currentLayer: dashBoard.currentLayer
  }

  function displayToast( message, type ) {
    //toastMessage.text = message
    if( !welcomeScreen.visible )
      toast.show(message, type)
  }

  Rectangle {
    id: busyMessage
    anchors.fill: parent
    color: Theme.darkGray
    opacity: 0
    visible: false

    state: "hidden"
    states: [
        State {
            name: "hidden"
            PropertyChanges { target: busyMessage; opacity: 0 }
            PropertyChanges { target: busyMessage; visible: false }
        },

        State {
            name: "visible"
            PropertyChanges { target: busyMessage; visible: true }
            PropertyChanges { target: busyMessage; opacity: 0.75 }
        }]
    transitions: [
        Transition {
            from: "hidden"
            to: "visible"
            SequentialAnimation {
                PropertyAnimation { target: busyMessage; property: "visible"; duration: 0 }
                NumberAnimation { target: busyMessage; easing.type: Easing.InOutQuad; properties: "opacity"; duration: 250 }
            }
        },
        Transition {
            from: "visible"
            to: "hidden"
            SequentialAnimation {
                PropertyAnimation { target: busyMessage; easing.type: Easing.InOutQuad; property: "opacity"; duration: 250 }
                PropertyAnimation { target: busyMessage; property: "visible"; duration: 0 }
            }
        }
    ]

    BusyIndicator {
      id: busyMessageIndicator
      anchors.centerIn: parent
      running: true
      width: 100
      height: 100
    }

    Text {
      id: busyMessageText
      anchors.top: busyMessageIndicator.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      horizontalAlignment: Text.AlignHCenter
      font: Theme.tipFont
      color: Theme.mainColor
      text: ''
    }

    Timer {
      id: readProjectTimer

      interval: 250
      repeat: false
      onTriggered: iface.readProject()
    }

    Connections {
      target: iface

      function onLoadProjectTriggered(path,name) {
        qfieldLocalDataPickerScreen.visible = false
        qfieldLocalDataPickerScreen.focus = false
        welcomeScreen.visible = false
        welcomeScreen.focus = false

        dashBoard.layerTree.freeze()
        mapCanvasMap.freeze('projectload')

        busyMessageText.text = qsTr( "Loading %1" ).arg( name !== '' ? name : path )
        busyMessage.state = "visible"

        navigation.clearDestinationFeature();

        projectInfo.filePath = '';
        readProjectTimer.start()
      }

      function onLoadProjectEnded(path,name) {
        mapCanvasMap.unfreeze('projectload')
        busyMessage.state = "hidden"

        projectInfo.filePath = path;

        mapCanvasBackground.color = mapCanvas.mapSettings.backgroundColor

        recentProjectListModel.reloadModel()

        var cloudProjectId = QFieldCloudUtils.getProjectId(qgisProject.fileName)
        cloudProjectsModel.currentProjectId = cloudProjectId
        cloudProjectsModel.refreshProjectModification(cloudProjectId)
        if (cloudProjectId != '') {
          var cloudProjectData = cloudProjectsModel.getProjectData(cloudProjectId)
          switch(cloudProjectData.UserRole) {
            case 'reader':
              stateMachine.state = "browse"
              projectInfo.hasInsertRights = false
              projectInfo.hasEditRights = false
              break;
            case 'reporter':
              projectInfo.hasInsertRights = true
              projectInfo.hasEditRights = false
              break;
            case 'editor':
            case 'manager':
            case 'admin':
              projectInfo.hasInsertRights = true
              projectInfo.hasEditRights = true
              break;
            default:
              projectInfo.hasInsertRights = true
              projectInfo.hasEditRights = true
              break;
          }

          if (cloudProjectsModel.layerObserver.deltaFileWrapper.hasError()) {
            cloudPopup.show()
          }
        } else {
          projectInfo.hasInsertRights = true
          projectInfo.hasEditRights = true
        }

        if (stateMachine.state === "digitize") {
            dashBoard.ensureEditableLayerSelected();
        }

        projectInfo.reprojectDisplayCoordinatesToWGS84 = !mapCanvas.mapSettings.destinationCrs.isGeographic
                                                         && iface.readProjectEntry("PositionPrecision", "/DegreeFormat", "MU") !== "MU"

        layoutListInstantiator.model.project = qgisProject
        layoutListInstantiator.model.reloadModel()
        printMenu.enablePrintItem(layoutListInstantiator.model.rowCount())

        settings.setValue( "/QField/FirstRunFlag", false )
      }

      function onSetMapExtent(extent) {
          mapCanvas.mapSettings.extent = extent;
      }
    }
  }

  ProjectInfo {
    id: projectInfo

    mapSettings: mapCanvas.mapSettings
    layerTree: dashBoard.layerTree

    property bool reprojectDisplayCoordinatesToWGS84: false

    property bool hasInsertRights: true
    property bool hasEditRights: true

    property bool insertRights: hasInsertRights && (cloudProjectsModel.currentProjectId == '' || cloudProjectsModel.currentProjectData.Status === QFieldCloudProjectsModel.Idle)
    property bool editRights: hasEditRights && (cloudProjectsModel.currentProjectId == '' || cloudProjectsModel.currentProjectData.Status === QFieldCloudProjectsModel.Idle)
  }

  BusyIndicator {
    id: busyIndicator
    anchors.left: mainMenuBar.left
    anchors.top: mainToolbar.bottom
    width: mainMenuBar.height
    height: mainMenuBar.height
    running: mapCanvasMap.isRendering
  }

  MessageLog {
    id: messageLog
    anchors.fill: parent
    focus: visible
    visible: false

    model: messageLogModel

    onFinished: {
      visible = false
    }

    Keys.onReleased: {
      if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
        event.accepted = true
        visible = false
      }
    }

    Component.onCompleted: {
      focusstack.addFocusTaker( this )
      unreadMessages = messageLogModel.rowCount !== 0
    }
  }

  BadLayerItem {
    id: badLayersView

    anchors.fill: parent
    model: BadLayerHandler {
      project: qgisProject

      onBadLayersFound: {
        badLayersView.visible = true
      }
    }

    visible: false

    onFinished: {
      visible = false
    }
  }

  Item {
    id: layerLogin

    Connections {
      target: iface

      function onLoadProjectEnded() {
        dashBoard.layerTree.unfreeze( true );
        if( !qfieldAuthRequestHandler.handleLayerLogins() )
        {
          //project loaded without more layer handling needed
          messageLogModel.unsuppressTags(["WFS","WMS"])
        }
      }
    }
    Connections {
        target: iface

        function onLoadProjectTriggered(path) {
          messageLogModel.suppressTags(["WFS","WMS"])
        }
    }

    Connections {
      target: qfieldAuthRequestHandler

      function onShowLoginDialog(realm) {
          loginDialogPopup.realm = realm || ""
          badLayersView.visible = false
          loginDialogPopup.open()
      }

      function onReloadEverything() {
          iface.reloadProject()
      }

      function onShowLoginBrowser(url) {
          loginBrowserPopup.url = url;
          loginBrowserPopup.open();
      }

      function onHideLoginBrowser() {
          loginBrowserPopup.close();
      }
    }

    Popup {
        id: loginBrowserPopup
        parent: ApplicationWindow.overlay

        property alias url: browserPanel.url

        x: 24
        y: 24
        width: parent.width - 48
        height: parent.height - 48
        padding: 0
        modal: true
        closePolicy: Popup.CloseOnEscape

        BrowserPanel {
            id: browserPanel
            anchors.fill: parent
            visible: true

            onCancel: {
                qfieldAuthRequestHandler.abortAuthBrowser();
                loginBrowserPopup.close();
            }
        }
    }

    Popup {
      id: loginDialogPopup
      parent: ApplicationWindow.overlay

      property var realm: ""

      x: 24
      y: 24
      width: parent.width - 48
      height: parent.height - 48
      padding: 0
      modal: true
      closePolicy: Popup.CloseOnEscape

      LayerLoginDialog {
        id: loginDialog

        anchors.fill: parent

        visible: true

        realm: loginDialogPopup.realm
        inCancelation: false

        onEnter: {
          qfieldAuthRequestHandler.enterCredentials( realm, usr, pw)
          inCancelation = false;
          loginDialogPopup.close()
        }
        onCancel: {
          inCancelation = true;
          loginDialogPopup.close(true)
        }
      }

      onClosed: {
        // handled here with parameter inCancelation because the loginDialog needs to be closed before the signal is fired
        qfieldAuthRequestHandler.loginDialogClosed(loginDialog.realm, loginDialog.inCancelation )
      }
    }

  }

  About {
    id: aboutDialog
    anchors.fill: parent
    focus: visible

    visible: false

    Keys.onReleased: {
      if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
        event.accepted = true
        visible = false
      }
    }

    Component.onCompleted: focusstack.addFocusTaker( this )
  }

  QFieldSettings {
    id: qfieldSettings

    anchors.fill: parent
    visible: false
    focus: visible

    onFinished: {
      visible = false
    }

    Keys.onReleased: {
      if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
        event.accepted = true
        finished()
      }
    }

    onDimBrightnessChanged: iface.setScreenDimmerActive( qfieldSettings.dimBrightness )
    Component.onCompleted: focusstack.addFocusTaker( this )
  }

  QFieldCloudConnection {
    id: cloudConnection

    property int previousStatus: QFieldCloudConnection.Disconnected

    onStatusChanged: {
      if (cloudConnection.status === QFieldCloudConnection.Disconnected && previousStatus === QFieldCloudConnection.LoggedIn) {
        displayToast(qsTr('Signed out'))
      } else if (cloudConnection.status === QFieldCloudConnection.Connecting) {
        displayToast(qsTr('Connecting...'))
      } else if (cloudConnection.status === QFieldCloudConnection.LoggedIn) {
        displayToast(qsTr('Signed in'))
      }
      previousStatus = cloudConnection.status
    }
    onLoginFailed: function(reason) { displayToast( reason ) }
  }

  QFieldCloudProjectsModel {
    id: cloudProjectsModel
    cloudConnection: cloudConnection
    layerObserver: layerObserverAlias
    gpkgFlusher: gpkgFlusherAlias

    onProjectDownloaded: function ( projectId, projectName, hasError, errorString ) {
      return hasError
          ? displayToast( qsTr( "Project %1 failed to download" ).arg( projectName ), 'error' )
          : displayToast( qsTr( "Project %1 successfully downloaded, it's now available to open" ).arg( projectName ) );
    }

    onPushFinished: function ( projectId, hasError, errorString ) {
      if ( hasError ) {
        displayToast( qsTr( "Changes failed to reach QFieldCloud: %1" ).arg( errorString ), 'error' )
        return;
      }

      displayToast( qsTr( "Changes successfully pushed to QFieldCloud" ) )
    }

    onWarning: displayToast( message )

    onDeltaListModelChanged: function () {
      qfieldCloudDeltaHistory.model = cloudProjectsModel.currentProjectData.DeltaList
    }
  }

  QFieldCloudDeltaHistory {
      id: qfieldCloudDeltaHistory

      modal: true
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
      parent: ApplicationWindow.overlay
  }

  QFieldCloudScreen {
    id: qfieldCloudScreen

    anchors.fill: parent
    visible: false
    focus: visible

    onFinished: {
      visible = false
      welcomeScreen.visible = true
    }

    Component.onCompleted: focusstack.addFocusTaker( this )
  }

  QFieldCloudPopup {
    id: cloudPopup
    visible: false
    focus: visible
    parent: ApplicationWindow.overlay

    width: parent.width
    height: parent.height
  }

  QFieldCloudPackageLayersFeedback {
    id: cloudPackageLayersFeedback
    visible: false
    parent: ApplicationWindow.overlay

    width: parent.width
    height: parent.height
  }

  QFieldLocalDataPickerScreen {
    id: qfieldLocalDataPickerScreen

    anchors.fill: parent
    visible: false
    focus: visible

    onFinished: {
      visible = false
      if (model.currentPath === 'root') {
        welcomeScreen.visible = loading ? false : true
      }
    }

    Component.onCompleted: focusstack.addFocusTaker( this )
  }

  WelcomeScreen {
    id: welcomeScreen
    objectName: 'welcomeScreen'
    model: RecentProjectListModel {
      id: recentProjectListModel
    }
    property ProjectSource __projectSource

    anchors.fill: parent
    focus: true

    visible: true

    onOpenLocalDataPicker: {
      if (platformUtilities.capabilities & PlatformUtilities.CustomLocalDataPicker) {
        welcomeScreen.visible = false
        qfieldLocalDataPickerScreen.projectFolderView = false
        qfieldLocalDataPickerScreen.model.resetToRoot()
        qfieldLocalDataPickerScreen.visible = true
      } else {
        __projectSource = platformUtilities.openProject(this)
      }
    }

    onShowQFieldCloudScreen: {
      welcomeScreen.visible = false
      qfieldCloudScreen.visible = true
    }

    Keys.onReleased: {
      if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
        if ( qgisProject.fileName != '') {
          event.accepted = true
          visible = false
          focus = false
        } else {
          event.accepted = false
          mainWindow.close()
        }
      }
    }

    Component.onCompleted: {
        focusstack.addFocusTaker( this )
    }
  }

  Changelog {
    id: changelogPopup
    parent: ApplicationWindow.overlay

    property var expireDate: new Date(2038,1,19)
    visible: settings && settings.value( "/QField/ChangelogVersion", "" ) !== appVersion && expireDate > new Date()
  }

  // Toast
  Popup {
      id: toast
      opacity: 0
      height: 40;
      width: parent.width
      y: parent.height - 112
      z: 10001
      margins: 0
      closePolicy: Popup.NoAutoClose

      background: Rectangle { color: "transparent" }

      function show(text, type) {
          toastMessage.text = text
          toastContent.type = type || 'info'
          toast.open()
          toastContent.visible = true
          toast.opacity = 1
          toastTimer.restart()
      }

      Behavior on opacity {
        NumberAnimation { duration: 250 }
      }

      Rectangle {
        id: toastContent
        color: "#66212121"

        property var type: 'info'

        height: toastMessage.height
        width: 30 + toastMessage.text.length * toastFontMetrics.averageCharacterWidth > mainWindow.width
               ? mainWindow.width - 16
               : 30 + toastMessage.text.length * toastFontMetrics.averageCharacterWidth

        anchors.centerIn: parent

        radius: 4

        z: 1

        Rectangle {
          id: toastIndicator
          anchors.left: parent.left
          anchors.leftMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          width:  10
          height: 10
          radius: 5
          color: toastContent.type === 'error' ? Theme.errorColor : Theme.warningColor
          visible: toastContent.type != 'info'
        }

        Text {
          id: toastMessage
          anchors.left: parent.left
          anchors.right: parent.right
          wrapMode: Text.Wrap
          leftPadding: 18
          rightPadding: 18
          topPadding: 3
          bottomPadding: 3
          color: Theme.light

          font: Theme.secondaryTitleFont
          horizontalAlignment: Text.AlignHCenter
        }
      }

      FontMetrics {
          id: toastFontMetrics
          font: toastMessage.font
      }

      // Visible only for 3 seconds
      Timer {
          id: toastTimer
          interval: 3000
          onTriggered: {
              toast.opacity = 0
          }
      }

      onOpacityChanged: {

          if ( opacity == 0 ) {
              toastContent.visible = false
              toast.close()
          }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
            toast.close()
            toast.opacity = 0
        }
      }
  }

  DropArea {
    id: dropArea
    anchors.fill: parent
    onEntered: {
      if ( drag.urls.length !== 1 || !iface.isFileExtensionSupported( drag.urls[0] ) ) {
          drag.accepted = false
      }
      else {
        drag.accept (Qt.CopyAction)
        drag.accepted = true
      }
    }
    onDropped: {
      iface.loadFile( drop.urls[0] )
    }
  }

  property bool alreadyCloseRequested: false

  onClosing: {
      if( !alreadyCloseRequested )
      {
        close.accepted = false
        alreadyCloseRequested = true
        displayToast( qsTr( "Press back again to close project and app" ) )
        closingTimer.start()
      }
      else
      {
        close.accepted = true
      }
  }

  Timer {
    id: closingTimer
    interval: 2000
    onTriggered: {
        alreadyCloseRequested = false
    }
  }

  Connections {
    target: welcomeScreen.__projectSource

    function onProjectOpened(path) {
      iface.loadFile(path)
    }
  }

  // ! MODELS !
  FeatureModel {
    id: geometryEditingFeature
    project: qgisProject
    currentLayer: null
    positionInformation: positionSource.positionInformation
    positionLocked: positionSource.active && positioningSettings.positioningCoordinateLock
    vertexModel: vertexModel
    cloudUserInformation: cloudConnection.userInformation
  }

  VertexModel {
      id: vertexModel
      currentPoint: coordinateLocator.currentCoordinate
      mapSettings: mapCanvas.mapSettings
      isHovering: hoverHandler.hovered
  }
}
