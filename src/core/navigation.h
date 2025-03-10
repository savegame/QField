/***************************************************************************
 navigation.h - Navigation

 ---------------------
 begin                : 22.02.2022
 copyright            : (C) 2022 by Mathieu Pellerin
 email                : mathieu (at) opengis.ch
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#ifndef NAVIGATION_H
#define NAVIGATION_H

#include "navigationmodel.h"
#include "qgsquickmapsettings.h"

#include <QObject>
#include <qgsdistancearea.h>

class Navigation : public QObject
{
    Q_OBJECT

    Q_PROPERTY( QgsQuickMapSettings *mapSettings READ mapSettings WRITE setMapSettings NOTIFY mapSettingsChanged )
    Q_PROPERTY( NavigationModel *model READ model() NOTIFY modelChanged )

    Q_PROPERTY( QgsPoint location READ location WRITE setLocation NOTIFY locationChanged )
    Q_PROPERTY( QgsPoint destination READ destination WRITE setDestination NOTIFY destinationChanged )
    Q_PROPERTY( QString destinationName READ destinationName NOTIFY destinationNameChanged )

    Q_PROPERTY( QgsGeometry path READ path NOTIFY detailsChanged )
    Q_PROPERTY( double distance READ distance NOTIFY detailsChanged )
    Q_PROPERTY( QgsUnitTypes::DistanceUnit distanceUnits READ distanceUnits NOTIFY detailsChanged )
    Q_PROPERTY( double bearing READ bearing NOTIFY detailsChanged )

    Q_PROPERTY( int destinationFeatureCurrentVertex READ destinationFeatureCurrentVertex NOTIFY destinationFeatureCurrentVertexChanged )
    Q_PROPERTY( int destinationFeatureVertexCount READ destinationFeatureVertexCount NOTIFY destinationFeatureVertexCountChanged )

    Q_PROPERTY( bool isActive READ isActive NOTIFY isActiveChanged )

  public:
    Navigation();

    ~Navigation();

    bool isActive() const;

    void setMapSettings( QgsQuickMapSettings *mapSettings );
    QgsQuickMapSettings *mapSettings() const { return mMapSettings; }

    NavigationModel *model() const { return mModel.get(); }

    QgsPoint location() const;
    void setLocation( const QgsPoint &point );

    QgsPoint destination() const;
    void setDestination( const QgsPoint &point );
    QString destinationName() const;

    /**
     * Sets a provided feature as navigation destination, which allows for users to cycle through the
     * feature centroid and its individual vertices as destination point.
     * \param feature the feature used as destination
     * \param layer the vector layer associated to the feature
     */
    Q_INVOKABLE void setDestinationFeature( const QgsFeature &feature, QgsVectorLayer *layer );

    /**
     * Clears the current destination feature, as well as the current destination point.
     */
    Q_INVOKABLE void clearDestinationFeature();

    /**
     * Sets the destination point to the next vertex or centroid of the current destination feature.
     * \note if a destination feature has not been provided, calling this function does nothing
     */
    Q_INVOKABLE void nextDestinationVertex();

    /**
     * Sets the destination point to the previous vertex or centroid of the current destination feature.
     * \note if a destination feature has not been provided, calling this function does nothing
     */
    Q_INVOKABLE void previousDestinationVertex();

    int destinationFeatureCurrentVertex() const;
    int destinationFeatureVertexCount() const;

    QgsGeometry path() const { return mPath; }
    double distance() const { return mDistance; }
    QgsUnitTypes::DistanceUnit distanceUnits() const { return mDa.lengthUnits(); }
    double bearing() const { return mBearing; }

    Q_INVOKABLE void clear();

  signals:
    void isActiveChanged();

    void mapSettingsChanged();
    void modelChanged();

    void locationChanged();
    void destinationChanged();
    void destinationNameChanged();

    void destinationFeatureCurrentVertexChanged();
    void destinationFeatureVertexCountChanged();

    void detailsChanged();

  private slots:
    void crsChanged();

  private:
    void updateDetails();
    void setDestinationFromCurrentVertex();

    std::unique_ptr<NavigationModel> mModel = nullptr;
    QgsQuickMapSettings *mMapSettings = nullptr;
    QgsPoint mLocation;
    QgsGeometry mPath;
    QgsDistanceArea mDa;
    double mDistance = 0.0;
    double mBearing = 0.0;
    QString mDestinationName;

    QgsGeometry mGeometry;
    int mCurrentVertex = -1;
    int mVertexCount = 0;
};

#endif // NAVIGATION_H
