import QtQuick 2.5
import QtQuick.Controls 2.0
import org.qgis 1.0
import "../js/style.js" as Style
import ".." as QField
import QtQuick.Window 2.2

Item {
  signal valueChanged(var value, bool isNull)

  anchors.left: parent.left
  anchors.right: parent.right

  height: Math.max(image.height, button.height)

  property PictureSource __pictureSource

  Image {
    property var currentValue: value
    property var noimage: image.status === Image.Error ? Style.getThemeIcon("ic_broken_image_black_24dp") : Style.getThemeIcon("ic_photo_notavailable_white_48dp")

    id: image
    width: 200 * dp
    autoTransform: true
    fillMode: Image.PreserveAspectFit

    source: {
      if (image.status === Image.Error) {
          Style.getThemeIcon("ic_broken_image_black_24dp")
      } else if (image.currentValue) {
        'file://' + qgisProject.homePath + '/' + image.currentValue
      } else {
        Style.getThemeIcon("ic_photo_notavailable_white_48dp")
      }
    }

    MouseArea {
      anchors.fill: parent

      onClicked: {
        if (image.currentValue && settings.value("useNativeCamera", false))
          platformUtilities.open(image.currentValue, "image/*");
      }
    }

    onCurrentValueChanged: {
        console.log("source is "+image.source+" and value is "+value+" or "+image.currentValue+" but error is "+image.status+" ("+Image.Error+")")
    }
    onSourceChanged: {
        console.log("source is now "+image.source+" and noimage is "+image.noimage)
    }
    onStatusChanged: {
        console.log("status is now "+image.status+" and noimage is "+image.noimage)
    }

  }

  QField.Button {
    id: button
    width: 36 * dp
    height: 36 * dp

    anchors.right: parent.right
    anchors.bottom: parent.bottom

    bgcolor: "transparent"

    onClicked: {
      if ( settings.valueBool("useNativeCamera", false) ) {
        __pictureSource = platformUtilities.getPicture(qgisProject.homePath + '/DCIM')
      } else {
        platformUtilities.createDir( qgisProject.homePath, 'DCIM' )
        camloader.active = true
      }
    }

    iconSource: Style.getThemeIcon("ic_camera_alt_border_24dp")
  }

  Loader {
    id: camloader
    sourceComponent: camcomponent
    active: false
  }

  Component {
    id: camcomponent

    Popup {
      id: campopup

      Component.onCompleted: {
        if ( platformUtilities.checkCameraPermissions() )
          open()
      }

      parent: ApplicationWindow.overlay

      x: 0
      y: 0
      height: parent.height
      width: parent.width

      modal: true
      focus: true

      QField.QFieldCamera {
        id: qfieldCamera

        visible: true

        onFinished: {
          var timestamp = (new Date()).toISOString().replace(/[^0-9]/g, "")
          var filename = timestamp+'.jpg';
          platformUtilities.renameFile( path, qgisProject.homePath +'/DCIM/' + filename)
          valueChanged('DCIM/' + filename, false)
          campopup.close()
        }
        onCanceled: {
          campopup.close()
        }
      }
      onClosed: camloader.active = false
    }
  }

  Connections {
    target: __pictureSource
    onPictureReceived: {
      valueChanged('DCIM/' + path, false)
    }
  }
}
