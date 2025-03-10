import QtQuick 2.12
import Qt.labs.settings 1.0 as LabSettings

LabSettings.Settings {
    property bool positioningActivated: false
    property bool positioningCoordinateLock: false

    property string positioningDevice: ""
    property string positioningDeviceName: qsTr( "Internal device" );
    property bool ellipsoidalElevation: true

    property bool showPositionInformation: false

    property bool accuracyIndicator: false
    property real accuracyBad: 5.0
    property real accuracyExcellent: 1.0
    property bool accuracyRequirement: false

    property bool averagedPositioning: false
    property int  averagedPositioningMinimumCount: 1

    property real antennaHeight: 0.0
    property bool antennaHeightActivated: false
    property bool skipAltitudeCorrection: false

    property string verticalGrid: ""

    property bool trackerTimeIntervalConstraint: false
    property double trackerTimeInterval: 30
    property bool trackerMinimumDistanceConstraint: false
    property double trackerMinimumDistance: 30
    property bool trackerMeetAllConstraints: false
}
