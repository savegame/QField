/***************************************************************************
                            qgismobileapp.cpp
                              -------------------
              begin                : Wed Apr 04 10:48:28 CET 2012
              copyright            : (C) 2012 by Marco Bernasocchi
              email                : marco@bernawebdesign.ch
 ***************************************************************************/

/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#include <QApplication>

#ifndef _MSC_VER
#include <unistd.h>
#endif
#include <proj.h>
#include <stdlib.h>

// use GDAL VSI mechanism
#define CPL_SUPRESS_CPLUSPLUS //#spellok
#include "cpl_conv.h"
#include "cpl_string.h"
#include "cpl_vsi.h"

#include <QDateTime>
#include <QFontDatabase>
#include <QStandardItemModel>
#include <QStandardPaths>
#include <QSurfaceFormat>
#include <QtQml/QQmlApplicationEngine>
#include <QtQml/QQmlContext>
#include <QtQml/QQmlEngine>
#include <QtWidgets/QDesktopWidget>
#include <QtWidgets/QFileDialog> // Until native looking QML dialogs are implemented (Qt5.4?)
#include <QtWidgets/QMenu>       // Until native looking QML dialogs are implemented (Qt5.4?)
#include <QtWidgets/QMenuBar>
#ifndef QT_NO_PRINTER
#include <QPrintDialog>
#include <QPrinter>
#endif

#include "appinterface.h"
#include "attributeformmodel.h"
#include "badlayerhandler.h"
#include "bluetoothdevicemodel.h"
#include "bluetoothreceiver.h"
#include "changelogcontents.h"
#include "deltafilewrapper.h"
#include "deltalistmodel.h"
#include "digitizinglogger.h"
#include "distancearea.h"
#include "expressionevaluator.h"
#include "expressionvariablemodel.h"
#include "featurechecklistmodel.h"
#include "featurelistextentcontroller.h"
#include "featurelistmodel.h"
#include "featurelistmodelselection.h"
#include "featuremodel.h"
#include "featureutils.h"
#include "fileutils.h"
#include "geometry.h"
#include "geometryeditorsmodel.h"
#include "geometryutils.h"
#include "gnsspositioninformation.h"
#include "identifytool.h"
#include "layerobserver.h"
#include "layerresolver.h"
#include "layertreemapcanvasbridge.h"
#include "layertreemodel.h"
#include "layerutils.h"
#include "legendimageprovider.h"
#include "linepolygonhighlight.h"
#include "locatormodelsuperbridge.h"
#include "maptoscreen.h"
#include "messagelogmodel.h"
#include "modelhelper.h"
#include "navigation.h"
#include "navigationmodel.h"
#include "orderedrelationmodel.h"
#include "picturesource.h"
#include "printlayoutlistmodel.h"
#include "projectinfo.h"
#include "projectsource.h"
#include "qfield.h"
#include "qfieldcloudconnection.h"
#include "qfieldcloudprojectsmodel.h"
#include "qfieldcloudutils.h"
#include "qgismobileapp.h"
#include "qgsgeometrywrapper.h"
#include "qgsquickcoordinatetransformer.h"
#include "qgsquickmapcanvasmap.h"
#include "qgsquickmapsettings.h"
#include "qgsquickmaptransform.h"
#include "recentprojectlistmodel.h"
#include "referencingfeaturelistmodel.h"
#include "rubberband.h"
#include "rubberbandmodel.h"
#include "scalebarmeasurement.h"
#include "snappingresult.h"
#include "snappingutils.h"
#include "stringutils.h"
#include "submodel.h"
#include "trackingmodel.h"
#include "urlutils.h"
#include "valuemapmodel.h"
#include "vertexmodel.h"

#include <QFileInfo>
#include <QFontDatabase>
#include <QResource>
#include <QStyleHints>
#include <QTemporaryFile>
#include <qgsauthmanager.h>
#include <qgsbilinearrasterresampler.h>
#include <qgscoordinatereferencesystem.h>
#include <qgsexpressionfunction.h>
#include <qgsfeature.h>
#include <qgsfield.h>
#include <qgsfieldconstraints.h>
#include <qgsgeopackageprojectstorage.h>
#include <qgslayertree.h>
#include <qgslayertreemodel.h>
#include <qgslayoutatlas.h>
#include <qgslayoutitemmap.h>
#include <qgslayoutmanager.h>
#include <qgslayoutpagecollection.h>
#include <qgslocalizeddatapathregistry.h>
#include <qgslocator.h>
#include <qgslocatormodel.h>
#include <qgslogger.h>
#include <qgsmaplayer.h>
#include <qgsmapthemecollection.h>
#include <qgsnetworkaccessmanager.h>
#include <qgsofflineediting.h>
#include <qgsprintlayout.h>
#include <qgsproject.h>
#include <qgsprojectstorage.h>
#include <qgsprojectstorageregistry.h>
#include <qgsprojectviewsettings.h>
#include <qgsrasterlayer.h>
#include <qgsrasterresamplefilter.h>
#include <qgsrelationmanager.h>
#include <qgssinglesymbolrenderer.h>
#include <qgssnappingutils.h>
#include <qgsunittypes.h>
#include <qgsvectorlayer.h>
#include <qgsvectorlayereditbuffer.h>

#define QUOTE( string ) _QUOTE( string )
#define _QUOTE( string ) #string


QgisMobileapp::QgisMobileapp( QgsApplication *app, QObject *parent )
  : QQmlApplicationEngine( parent )
  , mIface( new AppInterface( this ) )
  , mFirstRenderingFlag( true )
{
  // Enables antialiasing in QML scenes
  QSurfaceFormat format;
  format.setSamples( 4 );
  QSurfaceFormat::setDefaultFormat( format );

  // Set a nicer default hyperlink color to be used in QML Text items
  QPalette palette = app->palette();
  palette.setColor( QPalette::Link, QColor( 128, 204, 40 ) );
  palette.setColor( QPalette::LinkVisited, QColor( 128, 204, 40 ) );
  app->setPalette( palette );

  QSettings settings;
  if ( PlatformUtilities::instance()->capabilities() & PlatformUtilities::AdjustBrightness )
  {
    mScreenDimmer = std::make_unique<ScreenDimmer>( app );
    mScreenDimmer->setActive( settings.value( QStringLiteral( "dimBrightness" ), true ).toBool() );
  }

  AppInterface::setInstance( mIface );

  //set the authHandler to qfield-handler
  std::unique_ptr<QgsNetworkAuthenticationHandler> handler;
  mAuthRequestHandler = new QFieldAppAuthRequestHandler();
  handler.reset( mAuthRequestHandler );
  QgsNetworkAccessManager::instance()->setAuthHandler( std::move( handler ) );

  QStringList dataDirs = PlatformUtilities::instance()->qfieldAppDataDirs();
  if ( !dataDirs.isEmpty() )
  {
    //set localized data paths and register fonts
    QStringList localizedDataPaths;
    for ( const QString &dataDir : dataDirs )
    {
      localizedDataPaths << dataDir + QStringLiteral( "basemaps/" );

      // set fonts)
      const QString fontsPath = dataDir + QStringLiteral( "fonts/" );
      QDir fontsDir( fontsPath );
      if ( fontsDir.exists() )
      {
        const QStringList fonts = fontsDir.entryList( QStringList() << "*.ttf"
                                                                    << "*.TTF"
                                                                    << "*.otf"
                                                                    << "*.OTF",
                                                      QDir::Files );
        for ( auto font : fonts )
        {
          QFontDatabase::addApplicationFont( fontsPath + font );
        }
      }
    }
    QgsApplication::instance()->localizedDataPathRegistry()->setPaths( localizedDataPaths );
  }

  QFontDatabase::addApplicationFont( ":/fonts/Cadastra-Bold.ttf" );
  QFontDatabase::addApplicationFont( ":/fonts/Cadastra-BoldItalic.ttf" );
  QFontDatabase::addApplicationFont( ":/fonts/Cadastra-Condensed.ttf" );
  QFontDatabase::addApplicationFont( ":/fonts/Cadastra-Italic.ttf" );
  QFontDatabase::addApplicationFont( ":/fonts/Cadastra-Regular.ttf" );
  QFontDatabase::addApplicationFont( ":/fonts/Cadastra-Semibolditalic.ttf" );
  QFontDatabase::addApplicationFont( ":/fonts/CadastraSymbol-Mask.ttf" );
  QFontDatabase::addApplicationFont( ":/fonts/CadastraSymbol-Regular.ttf" );

  mProject = QgsProject::instance();
  mGpkgFlusher = std::make_unique<QgsGpkgFlusher>( mProject );
  mLayerObserver = std::make_unique<LayerObserver>( mProject );
  mFlatLayerTree = new FlatLayerTreeModel( mProject->layerTreeRoot(), mProject, this );
  mLegendImageProvider = new LegendImageProvider( mFlatLayerTree->layerTreeModel() );
  mTrackingModel = new TrackingModel;

  mBookmarkModel = std::make_unique<BookmarkModel>( QgsApplication::bookmarkManager(), mProject->bookmarkManager(), nullptr );

  // Transition from 1.8 to 1.8.1+
  const QString deviceAddress = settings.value( QStringLiteral( "positioningDevice" ), QString() ).toString();
  if ( deviceAddress == QStringLiteral( "internal" ) )
  {
    settings.setValue( QStringLiteral( "positioningDevice" ), QString() );
  }

  // cppcheck-suppress leakReturnValNotUsed
  initDeclarative();

  if ( !dataDirs.isEmpty() )
  {
    // add extra proj search path to allow copying of transformation grid files
    QString path( proj_info().searchpath );
    QStringList paths;
#ifdef Q_OS_WIN
    paths = path.split( ';' );
#else
    paths = path.split( ':' );
#endif

    // thin out duplicates from paths -- see https://github.com/OSGeo/PROJ/pull/1498
    QSet<QString> existing;
    QStringList searchPaths;
    searchPaths.reserve( paths.count() );
    for ( QString &p : paths )
    {
      if ( existing.contains( p ) )
        continue;

      existing.insert( p );
      searchPaths << p;
    }

    for ( const QString &dataDir : dataDirs )
    {
      searchPaths << QStringLiteral( "%1/proj/" ).arg( dataDir );
    }
    char **newPaths = new char *[searchPaths.count()];
    for ( int i = 0; i < searchPaths.count(); ++i )
    {
      newPaths[i] = strdup( searchPaths.at( i ).toUtf8().constData() );
    }
    proj_context_set_search_paths( nullptr, searchPaths.count(), newPaths );
    for ( int i = 0; i < searchPaths.count(); ++i )
    {
      free( newPaths[i] );
    }
    delete[] newPaths;

#ifdef Q_OS_ANDROID
    for ( const QString &dataDir : dataDirs )
    {
      QFileInfo pgServiceFile( QStringLiteral( "%1/pg_service.conf" ).arg( dataDir ) );
      if ( pgServiceFile.exists() && pgServiceFile.isReadable() )
      {
        setenv( "PGSYSCONFDIR", dataDir.toUtf8(), true );
        break;
      }
    }
#endif

    QgsApplication::instance()->authManager()->setPasswordHelperEnabled( false );
    QgsApplication::instance()->authManager()->setMasterPassword( QString( "qfield" ) );
    // import authentication method configurations
    for ( const QString &dataDir : dataDirs )
    {
      QDir configurationsDir( QStringLiteral( "%1/auth" ).arg( dataDir ) );
      if ( configurationsDir.exists() )
      {
        const QStringList configurations = configurationsDir.entryList( QStringList() << QStringLiteral( "*.xml" ) << QStringLiteral( "*.XML" ), QDir::Files );
        for ( const QString &configuration : configurations )
        {
          qDebug() << QStringLiteral( "Importing authentication configuration file %1" ).arg( configurationsDir.absoluteFilePath( configuration ) );
          QgsApplication::instance()->authManager()->importAuthenticationConfigsFromXml( configurationsDir.absoluteFilePath( configuration ), QString(), true );
        }
      }
    }
  }

  PlatformUtilities::instance()->setScreenLockPermission( false );

  load( QUrl( "qrc:/qml/qgismobileapp.qml" ) );

  connect( this, &QQmlApplicationEngine::quit, app, &QgsApplication::quit );

  mMapCanvas = rootObjects().first()->findChild<QgsQuickMapCanvasMap *>();
  Q_ASSERT_X( mMapCanvas, "QML Init", "QgsQuickMapCanvasMap not found. It is likely that we failed to load the QML files. Check debug output for related messages." );

  mMapCanvas->mapSettings()->setProject( mProject );
  mBookmarkModel->setMapSettings( mMapCanvas->mapSettings() );

  QFieldCloudProjectsModel *qFieldCloudProjectsModel = rootObjects().first()->findChild<QFieldCloudProjectsModel *>();

  connect( qFieldCloudProjectsModel, &QFieldCloudProjectsModel::projectDownloaded, this, [=]( const QString &projectId, const QString &projectName, const bool hasError, const QString &errorString ) {
    Q_UNUSED( projectName )
    Q_UNUSED( errorString )
    if ( !hasError )
    {
      if ( projectId == QFieldCloudUtils::getProjectId( mProjectFilePath ) )
      {
        reloadProjectFile();
      }
    }
  } );

  mFlatLayerTree->layerTreeModel()->setLegendMapViewData( mMapCanvas->mapSettings()->mapSettings().mapUnitsPerPixel(),
                                                          static_cast<int>( std::round( mMapCanvas->mapSettings()->outputDpi() ) ), mMapCanvas->mapSettings()->mapSettings().scale() );

  connect( mProject, &QgsProject::readProject, this, &QgisMobileapp::onReadProject );

  mLayerTreeCanvasBridge = new LayerTreeMapCanvasBridge( mFlatLayerTree, mMapCanvas->mapSettings(), mTrackingModel, this );

  connect( this, &QgisMobileapp::loadProjectTriggered, mIface, &AppInterface::loadProjectTriggered );
  connect( this, &QgisMobileapp::loadProjectEnded, mIface, &AppInterface::loadProjectEnded );
  connect( this, &QgisMobileapp::setMapExtent, mIface, &AppInterface::setMapExtent );

  QTimer::singleShot( 1, this, &QgisMobileapp::onAfterFirstRendering );

  mOfflineEditing = new QgsOfflineEditing();

  mSettings.setValue( "/Map/searchRadiusMM", 5 );

  mAppMissingGridHandler = new AppMissingGridHandler( this );

  // Set GDAL option to fix loading of datasets within ZIP containers
  CPLSetConfigOption( "CPL_ZIP_ENCODING", "UTF-8" );
}

void QgisMobileapp::initDeclarative()
{
#if defined( Q_OS_ANDROID ) && QT_VERSION >= QT_VERSION_CHECK( 5, 14, 0 )
  QResource::registerResource( QStringLiteral( "assets:/android_rcc_bundle.rcc" ) );
#endif
  addImportPath( QStringLiteral( "qrc:/qml/imports" ) );

  // Register QGIS QML types
  qmlRegisterType<QgsSnappingUtils>( "org.qgis", 1, 0, "SnappingUtils" );
  qmlRegisterType<QgsMapLayerProxyModel>( "org.qgis", 1, 0, "MapLayerModel" );
  qmlRegisterType<QgsVectorLayer>( "org.qgis", 1, 0, "VectorLayer" );
  qmlRegisterType<QgsMapThemeCollection>( "org.qgis", 1, 0, "MapThemeCollection" );
  qmlRegisterType<QgsLocatorProxyModel>( "org.qgis", 1, 0, "QgsLocatorProxyModel" );
  qmlRegisterType<QgsVectorLayerEditBuffer>( "org.qgis", 1, 0, "QgsVectorLayerEditBuffer" );

  qRegisterMetaType<QgsGeometry>( "QgsGeometry" );
  qRegisterMetaType<QgsFeature>( "QgsFeature" );
  qRegisterMetaType<QgsPoint>( "QgsPoint" );
  qRegisterMetaType<QgsPointXY>( "QgsPointXY" );
  qRegisterMetaType<QgsPointSequence>( "QgsPointSequence" );
  qRegisterMetaType<QgsCoordinateTransformContext>( "QgsCoordinateTransformContext" );
  qRegisterMetaType<QgsWkbTypes::GeometryType>( "QgsWkbTypes::GeometryType" ); // could be removed since we have now qmlRegisterUncreatableType<QgsWkbTypes> ?
  qRegisterMetaType<QgsWkbTypes::Type>( "QgsWkbTypes::Type" );                 // could be removed since we have now qmlRegisterUncreatableType<QgsWkbTypes> ?
  qRegisterMetaType<QgsMapLayerType>( "QgsMapLayerType" );                     // could be removed since we have now qmlRegisterUncreatableType<QgsWkbTypes> ?
  qRegisterMetaType<QgsFeatureId>( "QgsFeatureId" );
  qRegisterMetaType<QgsAttributes>( "QgsAttributes" );
  qRegisterMetaType<QgsSnappingConfig>( "QgsSnappingConfig" );
  qRegisterMetaType<QgsUnitTypes::DistanceUnit>( "QgsUnitTypes::DistanceUnit" );
  qRegisterMetaType<QgsUnitTypes::AreaUnit>( "QgsUnitTypes::AreaUnit" );
  qRegisterMetaType<QgsRelation>( "QgsRelation" );
#if _QGIS_VERSION_INT >= 31900
  qRegisterMetaType<QgsPolymorphicRelation>( "QgsPolymorphicRelation" );
#endif
  qRegisterMetaType<PlatformUtilities::Capabilities>( "PlatformUtilities::Capabilities" );
  qRegisterMetaType<QgsField>( "QgsField" );
  qRegisterMetaType<QVariant::Type>( "QVariant::Type" );
  qRegisterMetaType<QgsDefaultValue>( "QgsDefaultValue" );
  qRegisterMetaType<QgsFieldConstraints>( "QgsFieldConstraints" );
  qRegisterMetaType<GeometryUtils::GeometryOperationResult>( "GeometryOperationResult" );
  qRegisterMetaType<QFieldCloudConnection::ConnectionStatus>( "QFieldCloudConnection::ConnectionStatus" );
  qRegisterMetaType<CloudUserInformation>( "CloudUserInformation" );
  qRegisterMetaType<QFieldCloudProjectsModel::ProjectStatus>( "QFieldCloudProjectsModel::ProjectStatus" );
  qRegisterMetaType<QFieldCloudProjectsModel::ProjectCheckout>( "QFieldCloudProjectsModel::ProjectCheckout" );
  qRegisterMetaType<QFieldCloudProjectsModel::ProjectModification>( "QFieldCloudProjectsModel::ProjectModification" );

  qmlRegisterUncreatableType<QgsProject>( "org.qgis", 1, 0, "Project", "" );
  qmlRegisterUncreatableType<QgsCoordinateReferenceSystem>( "org.qgis", 1, 0, "CoordinateReferenceSystem", "" );
  qmlRegisterUncreatableType<QgsUnitTypes>( "org.qgis", 1, 0, "QgsUnitTypes", "" );
  qmlRegisterUncreatableType<QgsRelationManager>( "org.qgis", 1, 0, "RelationManager", "The relation manager is available from the QgsProject. Try `qgisProject.relationManager`" );
  qmlRegisterUncreatableType<QgsWkbTypes>( "org.qgis", 1, 0, "QgsWkbTypes", "" );
  qmlRegisterUncreatableType<QgsMapLayer>( "org.qgis", 1, 0, "MapLayer", "" );
  qmlRegisterUncreatableType<QgsVectorLayer>( "org.qgis", 1, 0, "VectorLayerStatic", "" );

  // Register QgsQuick QML types
  qmlRegisterType<QgsQuickMapCanvasMap>( "org.qgis", 1, 0, "MapCanvasMap" );
  qmlRegisterType<QgsQuickMapSettings>( "org.qgis", 1, 0, "MapSettings" );
  qmlRegisterType<QgsQuickCoordinateTransformer>( "org.qfield", 1, 0, "CoordinateTransformer" );

  qmlRegisterType<QgsQuickMapTransform>( "org.qgis", 1, 0, "MapTransform" );

  // Register QField QML types
  qmlRegisterType<MultiFeatureListModel>( "org.qgis", 1, 0, "MultiFeatureListModel" );
  qmlRegisterType<FeatureListModel>( "org.qgis", 1, 0, "FeatureListModel" );
  qmlRegisterType<FeatureListModelSelection>( "org.qgis", 1, 0, "FeatureListModelSelection" );
  qmlRegisterType<FeatureListExtentController>( "org.qgis", 1, 0, "FeaturelistExtentController" );
  qmlRegisterType<Geometry>( "org.qgis", 1, 0, "Geometry" );
  qmlRegisterType<ModelHelper>( "org.qgis", 1, 0, "ModelHelper" );
  qmlRegisterType<Rubberband>( "org.qgis", 1, 0, "Rubberband" );
  qmlRegisterType<RubberbandModel>( "org.qgis", 1, 0, "RubberbandModel" );
  qmlRegisterType<PictureSource>( "org.qgis", 1, 0, "PictureSource" );
  qmlRegisterType<ProjectInfo>( "org.qgis", 1, 0, "ProjectInfo" );
  qmlRegisterType<ProjectSource>( "org.qgis", 1, 0, "ProjectSource" );
  qmlRegisterType<ViewStatus>( "org.qgis", 1, 0, "ViewStatus" );
  qmlRegisterType<MessageLogModel>( "org.qgis", 1, 0, "MessageLogModel" );

  qmlRegisterType<DigitizingLogger>( "org.qfield", 1, 0, "DigitizingLogger" );
  qmlRegisterType<AttributeFormModel>( "org.qfield", 1, 0, "AttributeFormModel" );
  qmlRegisterType<FeatureModel>( "org.qfield", 1, 0, "FeatureModel" );
  qmlRegisterType<IdentifyTool>( "org.qfield", 1, 0, "IdentifyTool" );
  qmlRegisterType<SubModel>( "org.qfield", 1, 0, "SubModel" );
  qmlRegisterType<ExpressionVariableModel>( "org.qfield", 1, 0, "ExpressionVariableModel" );
  qmlRegisterType<BadLayerHandler>( "org.qfield", 1, 0, "BadLayerHandler" );
  qmlRegisterType<SnappingUtils>( "org.qfield", 1, 0, "SnappingUtils" );
  qmlRegisterType<DistanceArea>( "org.qfield", 1, 0, "DistanceArea" );
  qmlRegisterType<FocusStack>( "org.qfield", 1, 0, "FocusStack" );
  qmlRegisterType<PrintLayoutListModel>( "org.qfield", 1, 0, "PrintLayoutListModel" );
  qmlRegisterType<VertexModel>( "org.qfield", 1, 0, "VertexModel" );
  qmlRegisterType<MapToScreen>( "org.qfield", 1, 0, "MapToScreen" );
  qmlRegisterType<LocatorModelSuperBridge>( "org.qfield", 1, 0, "LocatorModelSuperBridge" );
  qmlRegisterType<LocatorActionsModel>( "org.qfield", 1, 0, "LocatorActionsModel" );
  qmlRegisterType<LocatorFiltersModel>( "org.qfield", 1, 0, "LocatorFiltersModel" );
  qmlRegisterType<LinePolygonHighlight>( "org.qfield", 1, 0, "LinePolygonHighlight" );
  qmlRegisterType<QgsGeometryWrapper>( "org.qfield", 1, 0, "QgsGeometryWrapper" );
  qmlRegisterType<ValueMapModel>( "org.qfield", 1, 0, "ValueMapModel" );
  qmlRegisterType<RecentProjectListModel>( "org.qgis", 1, 0, "RecentProjectListModel" );
  qmlRegisterType<ReferencingFeatureListModel>( "org.qgis", 1, 0, "ReferencingFeatureListModel" );
  qmlRegisterType<OrderedRelationModel>( "org.qfield", 1, 0, "OrderedRelationModel" );
  qmlRegisterType<FeatureCheckListModel>( "org.qgis", 1, 0, "FeatureCheckListModel" );
  qmlRegisterType<GeometryEditorsModel>( "org.qfield", 1, 0, "GeometryEditorsModel" );
  qmlRegisterType<ExpressionEvaluator>( "org.qfield", 1, 0, "ExpressionEvaluator" );
  qmlRegisterType<BluetoothDeviceModel>( "org.qfield", 1, 0, "BluetoothDeviceModel" );
  qmlRegisterType<BluetoothReceiver>( "org.qfield", 1, 0, "BluetoothReceiver" );
  qmlRegisterType<ChangelogContents>( "org.qfield", 1, 0, "ChangelogContents" );
  qmlRegisterType<LayerResolver>( "org.qfield", 1, 0, "LayerResolver" );
  qmlRegisterType<QFieldCloudConnection>( "org.qfield", 1, 0, "QFieldCloudConnection" );
  qmlRegisterType<QFieldCloudProjectsModel>( "org.qfield", 1, 0, "QFieldCloudProjectsModel" );
  qmlRegisterType<QFieldCloudProjectsFilterModel>( "org.qfield", 1, 0, "QFieldCloudProjectsFilterModel" );
  qmlRegisterType<DeltaListModel>( "org.qfield", 1, 0, "DeltaListModel" );
  qmlRegisterType<ScaleBarMeasurement>( "org.qfield", 1, 0, "ScaleBarMeasurement" );
  qmlRegisterType<Navigation>( "org.qfield", 1, 0, "Navigation" );
  qmlRegisterType<NavigationModel>( "org.qfield", 1, 0, "NavigationModel" );

  qRegisterMetaType<GnssPositionInformation>( "GnssPositionInformation" );

  REGISTER_SINGLETON( "org.qfield", GeometryEditorsModel, "GeometryEditorsModelSingleton" );
  REGISTER_SINGLETON( "org.qfield", GeometryUtils, "GeometryUtils" );
  REGISTER_SINGLETON( "org.qfield", FeatureUtils, "FeatureUtils" );
  REGISTER_SINGLETON( "org.qfield", FileUtils, "FileUtils" );
  REGISTER_SINGLETON( "org.qfield", LayerUtils, "LayerUtils" );
  REGISTER_SINGLETON( "org.qfield", StringUtils, "StringUtils" );
  REGISTER_SINGLETON( "org.qfield", UrlUtils, "UrlUtils" );
  REGISTER_SINGLETON( "org.qfield", QFieldCloudUtils, "QFieldCloudUtils" );

  qmlRegisterUncreatableType<AppInterface>( "org.qgis", 1, 0, "QgisInterface", "QgisInterface is only provided by the environment and cannot be created ad-hoc" );
  qmlRegisterUncreatableType<Settings>( "org.qgis", 1, 0, "Settings", "" );
  qmlRegisterUncreatableType<PlatformUtilities>( "org.qfield", 1, 0, "PlatformUtilities", "" );
  qmlRegisterUncreatableType<FlatLayerTreeModel>( "org.qfield", 1, 0, "FlatLayerTreeModel", "The FlatLayerTreeModel is available as context property `flatLayerTree`." );
  qmlRegisterUncreatableType<TrackingModel>( "org.qfield", 1, 0, "TrackingModel", "The TrackingModel is available as context property `trackingModel`." );
  qmlRegisterUncreatableType<QgsGpkgFlusher>( "org.qfield", 1, 0, "QgsGpkgFlusher", "The gpkgFlusher is available as context property `gpkgFlusher`" );
  qmlRegisterUncreatableType<LayerObserver>( "org.qfield", 1, 0, "LayerObserver", "" );
  qmlRegisterUncreatableType<DeltaFileWrapper>( "org.qfield", 1, 0, "DeltaFileWrapper", "" );
  qmlRegisterUncreatableType<BookmarkModel>( "org.qfield", 1, 0, "BookmarkModel", "The BookmarkModel is available as context property `bookmarkModel`" );

  qRegisterMetaType<SnappingResult>( "SnappingResult" );

  // Calculate device pixels
  qreal dpi = std::max( QApplication::desktop()->logicalDpiY(), QApplication::desktop()->logicalDpiY() );
  dpi *= QApplication::desktop()->devicePixelRatioF();

  // Register some globally available variables
  rootContext()->setContextProperty( "ppi", dpi );
  rootContext()->setContextProperty( "mouseDoubleClickInterval", QApplication::styleHints()->mouseDoubleClickInterval() );
  rootContext()->setContextProperty( "qgisProject", mProject );
  rootContext()->setContextProperty( "bookmarkModel", mBookmarkModel.get() );
  rootContext()->setContextProperty( "iface", mIface );
  rootContext()->setContextProperty( "settings", &mSettings );
  rootContext()->setContextProperty( "appVersion", qfield::appVersion );
  rootContext()->setContextProperty( "appVersionStr", qfield::appVersionStr );
  rootContext()->setContextProperty( "gitRev", qfield::gitRev );
  rootContext()->setContextProperty( "flatLayerTree", mFlatLayerTree );
  rootContext()->setContextProperty( "platformUtilities", PlatformUtilities::instance() );
  rootContext()->setContextProperty( "CrsFactory", QVariant::fromValue<QgsCoordinateReferenceSystem>( mCrsFactory ) );
  rootContext()->setContextProperty( "UnitTypes", QVariant::fromValue<QgsUnitTypes>( mUnitTypes ) );
  rootContext()->setContextProperty( "ExifTools", QVariant::fromValue<QgsExifTools>( mExifTools ) );
  rootContext()->setContextProperty( "LocatorModelNoGroup", QgsLocatorModel::NoGroup );
  rootContext()->setContextProperty( "gpkgFlusher", mGpkgFlusher.get() );
  rootContext()->setContextProperty( "layerObserver", mLayerObserver.get() );

  rootContext()->setContextProperty( "qfieldAuthRequestHandler", mAuthRequestHandler );

  rootContext()->setContextProperty( "trackingModel", mTrackingModel );

  addImageProvider( QLatin1String( "legend" ), mLegendImageProvider );
}

void QgisMobileapp::loadProjectQuirks()
{
  // force update of canvas, without automatic changes to extent and OTF projections
  bool autoEnableCrsTransform = mLayerTreeCanvasBridge->autoEnableCrsTransform();
  bool autoSetupOnFirstLayer = mLayerTreeCanvasBridge->autoSetupOnFirstLayer();
  mLayerTreeCanvasBridge->setAutoEnableCrsTransform( false );
  mLayerTreeCanvasBridge->setAutoSetupOnFirstLayer( false );

  mLayerTreeCanvasBridge->setCanvasLayers();

  if ( autoEnableCrsTransform )
    mLayerTreeCanvasBridge->setAutoEnableCrsTransform( true );

  if ( autoSetupOnFirstLayer )
    mLayerTreeCanvasBridge->setAutoSetupOnFirstLayer( true );
}

void QgisMobileapp::removeRecentProject( const QString &path )
{
  QList<QPair<QString, QString>> projects = recentProjects();
  for ( int idx = 0; idx < projects.count(); idx++ )
  {
    if ( projects.at( idx ).second == path )
    {
      projects.removeAt( idx );
      break;
    }
  }
  saveRecentProjects( projects );
}

QList<QPair<QString, QString>> QgisMobileapp::recentProjects()
{
  QSettings settings;
  QList<QPair<QString, QString>> projects;

  settings.beginGroup( "/qgis/recentProjects" );
  const QStringList projectKeysList = settings.childGroups();
  QList<int> projectKeys;
  // This is overdoing it since we're clipping the recent projects list to five items at the moment, but might as well be futureproof
  for ( const QString &key : projectKeysList )
  {
    projectKeys.append( key.toInt() );
  }
  for ( int i = 0; i < projectKeys.count(); i++ )
  {
    settings.beginGroup( QString::number( projectKeys.at( i ) ) );
    projects << qMakePair( settings.value( QStringLiteral( "title" ) ).toString(), settings.value( QStringLiteral( "path" ) ).toString() );
    settings.endGroup();
  }
  settings.endGroup();
  return projects;
}

void QgisMobileapp::saveRecentProjects( QList<QPair<QString, QString>> &projects )
{
  QSettings settings;
  settings.remove( QStringLiteral( "/qgis/recentProjects" ) );
  for ( int idx = 0; idx < projects.count() && idx < 5; idx++ )
  {
    settings.beginGroup( QStringLiteral( "/qgis/recentProjects/%1" ).arg( idx ) );
    settings.setValue( QStringLiteral( "title" ), projects.at( idx ).first );
    settings.setValue( QStringLiteral( "path" ), projects.at( idx ).second );
    settings.endGroup();
  }
}

void QgisMobileapp::onReadProject( const QDomDocument &doc )
{
  Q_UNUSED( doc )
  QMap<QgsVectorLayer *, QgsFeatureRequest> requests;

  const QList<QgsMapLayer *> mapLayers { mProject->mapLayers().values() };
  for ( QgsMapLayer *layer : mapLayers )
  {
    QgsVectorLayer *vl = qobject_cast<QgsVectorLayer *>( layer );
    if ( vl )
    {
      const QVariant itinerary = vl->customProperty( "qgisMobile/itinerary" );
      if ( itinerary.isValid() )
      {
        requests.insert( vl, QgsFeatureRequest().setFilterExpression( itinerary.toString() ) );
      }
    }
  }
  if ( requests.count() )
  {
    qDebug() << QString( "Loading itinerary for %1 layers." ).arg( requests.count() );
    mIface->openFeatureForm();
  }
}

void QgisMobileapp::onAfterFirstRendering()
{
  // This should get triggered exactly once, so we disconnect it right away
  // disconnect( this, &QgisMobileapp::afterRendering, this, &QgisMobileapp::onAfterFirstRendering );

  if ( mFirstRenderingFlag )
  {
    if ( qApp->arguments().count() > 1 )
    {
      loadProjectFile( qApp->arguments().last() );
    }
    else if ( !PlatformUtilities::instance()->qgsProject().isNull() )
    {
      PlatformUtilities::instance()->checkWriteExternalStoragePermissions();
      loadProjectFile( PlatformUtilities::instance()->qgsProject() );
    }
    mFirstRenderingFlag = false;
  }
}

void QgisMobileapp::loadLastProject()
{
  QVariant lastProjectFile = QSettings().value( "/qgis/recentProjects/0/path" );
  if ( lastProjectFile.isValid() )
    loadProjectFile( lastProjectFile.toString() );
}

void QgisMobileapp::loadProjectFile( const QString &path, const QString &name )
{
  QFileInfo fi( path );
  if ( !fi.exists() )
    QgsMessageLog::logMessage( tr( "Project file \"%1\" does not exist" ).arg( path ), QStringLiteral( "QField" ), Qgis::Warning );

  const QString suffix = fi.suffix().toLower();
  if ( SUPPORTED_PROJECT_EXTENSIONS.contains( suffix ) || SUPPORTED_VECTOR_EXTENSIONS.contains( suffix ) || SUPPORTED_RASTER_EXTENSIONS.contains( suffix ) )
  {
    mAuthRequestHandler->clearStoredRealms();

    mProjectFilePath = path;
    mProjectFileName = !name.isEmpty() ? name : fi.completeBaseName();

    emit loadProjectTriggered( mProjectFilePath, mProjectFileName );
  }
}

void QgisMobileapp::reloadProjectFile()
{
  if ( mProjectFilePath.isEmpty() )
    QgsMessageLog::logMessage( tr( "No project file currently opened" ), QStringLiteral( "QField" ), Qgis::Warning );

  emit loadProjectTriggered( mProjectFilePath, mProjectFileName );
}

void QgisMobileapp::readProjectFile()
{
  QFileInfo fi( mProjectFilePath );
  if ( !fi.exists() )
    QgsMessageLog::logMessage( tr( "Project file \"%1\" does not exist" ).arg( mProjectFilePath ), QStringLiteral( "QField" ), Qgis::Warning );

  const QString suffix = fi.suffix().toLower();

  mProject->removeAllMapLayers();
  mProject->setTitle( QString() );

  mTrackingModel->reset();

  // load project file fonts if present
  QDir fontDir = QDir::cleanPath( QFileInfo( mProjectFilePath ).absoluteDir().path() + QDir::separator() + ".fonts" );
  QStringList fontExts = QStringList() << "*.ttf"
                                       << "*.TTF"
                                       << "*.otf"
                                       << "*.OTF";
  const QStringList fontFiles = fontDir.entryList( fontExts, QDir::Files );
  for ( const QString &fontFile : fontFiles )
  {
    int id = QFontDatabase::addApplicationFont( QDir::cleanPath( fontDir.path() + QDir::separator() + fontFile ) );
    qDebug() << QDir::cleanPath( fontDir.path() + QDir::separator() + fontFile );
    if ( id == -1 )
    {
      QgsMessageLog::logMessage( tr( "Could not load font %1" ).arg( fontFile ) );
    }
  }

  // Load project file
  bool projectLoaded = false;
  if ( SUPPORTED_PROJECT_EXTENSIONS.contains( suffix ) )
  {
    mProject->read( mProjectFilePath );
    projectLoaded = true;
  }
  else if ( suffix == QStringLiteral( "gpkg" ) )
  {
    QgsProjectStorage *storage = QgsApplication::projectStorageRegistry()->projectStorageFromType( "geopackage" );
    if ( storage )
    {
      const QStringList projectNames = storage->listProjects( mProjectFilePath );
      if ( !projectNames.isEmpty() )
      {
        QgsGeoPackageProjectUri projectUri { true, mProjectFilePath, projectNames.at( 0 ) };
        mProject->read( QgsGeoPackageProjectStorage::encodeUri( projectUri ) );
        projectLoaded = true;
      }
    }
  }

  QList<QPair<QString, QString>> projects = recentProjects();
  QString title;
  if ( mProject->fileName().startsWith( QFieldCloudUtils::localCloudDirectory() ) )
  {
    // Overwrite the title to match what is used in QField Cloud
    const QString projectId = fi.dir().dirName();
    title = QSettings().value( QStringLiteral( "QFieldCloud/projects/%1/name" ).arg( projectId ), fi.fileName() ).toString();
  }
  else
  {
    title = mProject->title().isEmpty() ? mProjectFileName : mProject->title();
  }

  QPair<QString, QString> project = qMakePair( title, mProjectFilePath );
  if ( projects.contains( project ) )
    projects.removeAt( projects.indexOf( project ) );
  projects.insert( 0, project );
  saveRecentProjects( projects );

  QList<QgsMapLayer *> vectorLayers;
  QList<QgsMapLayer *> rasterLayers;
  QgsCoordinateReferenceSystem crs;
  QgsRectangle extent;

  QStringList files;
  if ( suffix == QStringLiteral( "zip" ) )
  {
    // get list of files inside zip file
    QString tmpPath;
    char **papszSiblingFiles = VSIReadDirRecursive( QString( "/vsizip/" + mProjectFilePath ).toLocal8Bit().constData() );
    if ( papszSiblingFiles )
    {
      for ( int i = 0; papszSiblingFiles[i]; i++ )
      {
        tmpPath = papszSiblingFiles[i];
        // skip directories (files ending with /)
        if ( tmpPath.right( 1 ) != QLatin1String( "/" ) )
        {
          const QFileInfo tmpFi( tmpPath );
          if ( SUPPORTED_VECTOR_EXTENSIONS.contains( tmpFi.suffix().toLower() ) || SUPPORTED_RASTER_EXTENSIONS.contains( tmpFi.suffix().toLower() ) )
            files << QStringLiteral( "/vsizip/%1/%2" ).arg( mProjectFilePath, tmpPath );
        }
      }
      CSLDestroy( papszSiblingFiles );
    }
  }
  else if ( !projectLoaded )
  {
    files << mProjectFilePath;
  }

  for ( auto filePath : std::as_const( files ) )
  {
    const QString fileSuffix = QFileInfo( filePath ).suffix().toLower();
    // Load vector dataset
    if ( SUPPORTED_VECTOR_EXTENSIONS.contains( fileSuffix ) )
    {
      if ( suffix == QStringLiteral( "kmz" ) )
      {
        // GDAL's internal KML driver doesn't support KMZ, work around this limitation
        filePath = QStringLiteral( "/vsizip/%1/doc.kml" ).arg( mProjectFilePath );
      }

      QgsVectorLayer::LayerOptions options { QgsProject::instance()->transformContext() };
      options.loadDefaultStyle = true;

      QgsVectorLayer *layer = new QgsVectorLayer( filePath, mProjectFileName, QLatin1String( "ogr" ), options );
      if ( layer->isValid() )
      {
        const QStringList sublayers = layer->dataProvider()->subLayers();
        if ( sublayers.count() > 1 )
        {
          for ( const QString &sublayerInfo : sublayers )
          {
            const QStringList info = sublayerInfo.split( QgsDataProvider::sublayerSeparator() );
            QgsVectorLayer *sublayer = new QgsVectorLayer( QStringLiteral( "%1|layerid=%2" ).arg( filePath, info.at( 0 ) ),
                                                           QStringLiteral( "%1: %2" ).arg( mProjectFileName, info.at( 1 ) ),
                                                           QLatin1String( "ogr" ), options );
            if ( sublayer->isValid() )
            {
              if ( sublayer->crs().isValid() )
              {
                if ( !crs.isValid() )
                  crs = sublayer->crs();

                if ( !sublayer->extent().isEmpty() )
                {
                  if ( crs != sublayer->crs() )
                  {
                    QgsCoordinateTransform transform( sublayer->crs(), crs, mProject->transformContext() );
                    try
                    {
                      if ( extent.isEmpty() )
                        extent = transform.transformBoundingBox( sublayer->extent() );
                      else
                        extent.combineExtentWith( transform.transformBoundingBox( sublayer->extent() ) );
                    }
                    catch ( const QgsCsException &exp )
                    {
                      Q_UNUSED( exp )
                      // Ignore extent if it can't be transformed
                    }
                  }
                  else
                  {
                    if ( extent.isEmpty() )
                      extent = sublayer->extent();
                    else
                      extent.combineExtentWith( sublayer->extent() );
                  }
                }
              }
              vectorLayers << sublayer;
            }
            else
            {
              delete sublayer;
            }
          }
        }
        else
        {
          crs = layer->crs();
          extent = layer->extent();
          vectorLayers << layer;
        }

        for ( QgsMapLayer *l : std::as_const( vectorLayers ) )
        {
          QgsVectorLayer *vlayer = qobject_cast<QgsVectorLayer *>( l );
          bool ok;
          vlayer->loadDefaultStyle( ok );
          if ( !ok )
          {
            QgsSymbol *symbol = LayerUtils::defaultSymbol( vlayer );
            if ( symbol )
            {
              QgsSingleSymbolRenderer *renderer = new QgsSingleSymbolRenderer( symbol );
              vlayer->setRenderer( renderer );
            }
          }
          if ( !vlayer->labeling() )
          {
            QgsAbstractVectorLayerLabeling *labeling = LayerUtils::defaultLabeling( vlayer );
            if ( labeling )
            {
              vlayer->setLabeling( labeling );
              vlayer->setLabelsEnabled( vlayer->geometryType() == QgsWkbTypes::PointGeometry );
            }
          }
        }

        if ( vectorLayers.size() > 1 )
        {
          std::sort( vectorLayers.begin(), vectorLayers.end(), []( QgsMapLayer *a, QgsMapLayer *b ) {
            QgsVectorLayer *alayer = qobject_cast<QgsVectorLayer *>( a );
            QgsVectorLayer *blayer = qobject_cast<QgsVectorLayer *>( b );
            if ( alayer->geometryType() == QgsWkbTypes::PointGeometry && blayer->geometryType() != QgsWkbTypes::PointGeometry )
            {
              return true;
            }
            else if ( alayer->geometryType() == QgsWkbTypes::LineGeometry && blayer->geometryType() == QgsWkbTypes::PolygonGeometry )
            {
              return true;
            }
            else
            {
              return false;
            }
          } );
        }
      }
      else
      {
        delete layer;
      }
    }

    // Load raster dataset
    if ( SUPPORTED_RASTER_EXTENSIONS.contains( fileSuffix ) )
    {
      QgsRasterLayer *layer = new QgsRasterLayer( filePath, mProjectFileName, QLatin1String( "gdal" ) );
      if ( layer->isValid() )
      {
        const QStringList sublayers = layer->dataProvider()->subLayers();
        if ( sublayers.count() > 1 )
        {
          for ( const QString &sublayerInfo : sublayers )
          {
            const QStringList info = sublayerInfo.split( QgsDataProvider::sublayerSeparator() );
            QgsRasterLayer *sublayer = new QgsRasterLayer( QStringLiteral( "%1|layerid=%2" ).arg( filePath, info.at( 0 ) ),
                                                           QStringLiteral( "%1: %2" ).arg( mProjectFileName, info.at( 1 ) ),
                                                           QLatin1String( "gdal" ) );
            if ( sublayer->isValid() )
            {
              if ( sublayer->crs().isValid() )
              {
                if ( !crs.isValid() )
                  crs = sublayer->crs();

                if ( !sublayer->extent().isEmpty() )
                {
                  if ( crs != sublayer->crs() )
                  {
                    QgsCoordinateTransform transform( sublayer->crs(), crs, mProject->transformContext() );
                    try
                    {
                      if ( extent.isEmpty() )
                        extent = transform.transformBoundingBox( sublayer->extent() );
                      else
                        extent.combineExtentWith( transform.transformBoundingBox( sublayer->extent() ) );
                    }
                    catch ( const QgsCsException &exp )
                    {
                      Q_UNUSED( exp )
                      // Ignore extent if it can't be transformed
                    }
                  }
                  else
                  {
                    if ( extent.isEmpty() )
                      extent = sublayer->extent();
                    else
                      extent.combineExtentWith( sublayer->extent() );
                  }
                }
              }
              rasterLayers << sublayer;
            }
            else
            {
              delete sublayer;
            }
          }
        }
        else
        {
          crs = layer->crs();
          extent = layer->extent();
          rasterLayers << layer;
        }

        for ( QgsMapLayer *l : std::as_const( rasterLayers ) )
        {
          QgsRasterLayer *rlayer = qobject_cast<QgsRasterLayer *>( l );
          bool ok;
          rlayer->loadDefaultStyle( ok );
          if ( !ok && fi.size() < 50000000 )
          {
            // If the raster size is reasonably small, apply nicer resampling settings
            rlayer->resampleFilter()->setZoomedInResampler( new QgsBilinearRasterResampler() );
            rlayer->resampleFilter()->setZoomedOutResampler( new QgsBilinearRasterResampler() );
            rlayer->resampleFilter()->setMaxOversampling( 2.0 );
          }
        }
      }
    }
  }

  if ( vectorLayers.size() > 0 || rasterLayers.size() > 0 )
  {
    if ( crs.isValid() )
    {
      QSettings settings;
      const QString fileAssociationProject = settings.value( QStringLiteral( "QField/baseMapProject" ), QString() ).toString();
      if ( !fileAssociationProject.isEmpty() && QFile::exists( fileAssociationProject ) )
      {
        mProject->read( fileAssociationProject );
      }
      else
      {
        const QStringList dataDirs = PlatformUtilities::instance()->qfieldAppDataDirs();
        bool projectFound = false;
        for ( const QString &dataDir : dataDirs )
        {
          if ( QFile::exists( dataDir + QStringLiteral( "basemap.qgs" ) ) )
          {
            projectFound = true;
            mProject->read( dataDir + QStringLiteral( "basemap.qgs" ) );
            break;
          }
          else if ( QFile::exists( dataDir + QStringLiteral( "basemap.qgz" ) ) )
          {
            projectFound = true;
            mProject->read( dataDir + QStringLiteral( "basemap.qgs" ) );
            break;
          }
        }
        if ( !projectFound )
        {
          mProject->clear();

          // Add a default basemap
          QgsRasterLayer *layer = new QgsRasterLayer( QStringLiteral( "type=xyz&url=https://a.tile.openstreetmap.org/%7Bz%7D/%7Bx%7D/%7By%7D.png&zmax=19&zmin=0&crs=EPSG3857" ), QStringLiteral( "OpenStreetMap" ), QLatin1String( "wms" ) );
          mProject->addMapLayers( QList<QgsMapLayer *>() << layer );
        }
      }
    }
    else
    {
      mProject->clear();
    }

    mProject->setCrs( crs );
    mProject->setEllipsoid( crs.ellipsoidAcronym() );
    mProject->setTitle( mProjectFileName );

    mProject->addMapLayers( rasterLayers );
    mProject->addMapLayers( vectorLayers );
    if ( suffix.compare( QLatin1String( "pdf" ) ) == 0 )
    {
      // GeoPDFs should have vector layers hidden by default
      for ( QgsMapLayer *layer : vectorLayers )
      {
        mProject->layerTreeRoot()->findLayer( layer->id() )->setItemVisibilityChecked( false );
      }
    }
  }

  loadProjectQuirks();

  // Restore last extent if present
  QSettings settings;
  const QStringList parts = settings.value( QStringLiteral( "/qgis/projectInfo/%1/extent" ).arg( mProjectFilePath ), QString() ).toString().split( '|' );
  if ( parts.size() == 4 && ( SUPPORTED_PROJECT_EXTENSIONS.contains( fi.suffix().toLower() ) || fi.size() == settings.value( QStringLiteral( "/qgis/projectInfo/%1/filesize" ).arg( mProjectFilePath ), 0 ).toLongLong() ) )
  {
    extent.setXMinimum( parts[0].toDouble() );
    extent.setXMaximum( parts[1].toDouble() );
    extent.setYMinimum( parts[2].toDouble() );
    extent.setYMaximum( parts[3].toDouble() );
  }
  if ( !extent.isEmpty() && extent.width() != 0.0 )
  {
    // Add a bit of buffer so elements don't touch the map edges
    emit setMapExtent( extent.buffered( extent.width() * 0.02 ) );
  }

  const bool isTemporal = settings.value( QStringLiteral( "/qgis/projectInfo/%1/isTemporal" ).arg( mProjectFilePath ), false ).toBool();
  const QString begin = settings.value( QStringLiteral( "/qgis/projectInfo/%1/StartDateTime" ).arg( mProjectFilePath ), QString() ).toString();
  const QString end = settings.value( QStringLiteral( "/qgis/projectInfo/%1/EndDateTime" ).arg( mProjectFilePath ), QString() ).toString();
  if ( !begin.isEmpty() && !end.isEmpty() )
  {
    QDateTime beginDt = QDateTime::fromString( begin, Qt::ISODateWithMs );
    QDateTime endDt = QDateTime::fromString( end, Qt::ISODateWithMs );
    mMapCanvas->mapSettings()->setTemporalBegin( beginDt );
    mMapCanvas->mapSettings()->setTemporalEnd( endDt );
    mMapCanvas->mapSettings()->setIsTemporal( isTemporal );
  }

  // Restored last map theme if present
  const QString mapTheme = settings.value( QStringLiteral( "/qgis/projectInfo/%1/maptheme" ).arg( mProjectFilePath ), QString() ).toString();
  if ( !mapTheme.isEmpty() )
    mFlatLayerTree->setMapTheme( mapTheme );

  emit loadProjectEnded( mProjectFilePath, mProjectFileName );
}

QString QgisMobileapp::readProjectEntry( const QString &scope, const QString &key, const QString &def ) const
{
  if ( !mProject )
    return def;

  return mProject->readEntry( scope, key, def );
}

int QgisMobileapp::readProjectNumEntry( const QString &scope, const QString &key, int def ) const
{
  if ( !mProject )
    return def;

  return mProject->readNumEntry( scope, key, def );
}

double QgisMobileapp::readProjectDoubleEntry( const QString &scope, const QString &key, double def ) const
{
  if ( !mProject )
    return def;

  return mProject->readDoubleEntry( scope, key, def );
}

bool QgisMobileapp::print( const QString &layoutName )
{
#ifndef QT_NO_PRINTER
  const QList<QgsPrintLayout *> printLayouts = mProject->layoutManager()->printLayouts();
  QgsPrintLayout *layoutToPrint = nullptr;
  for ( QgsPrintLayout *layout : printLayouts )
  {
    if ( layout->name() == layoutName )
    {
      layoutToPrint = layout;
      break;
    }
  }

  if ( !layoutToPrint || layoutToPrint->pageCollection()->pageCount() == 0 )
    return false;

  if ( layoutToPrint->referenceMap() )
    layoutToPrint->referenceMap()->zoomToExtent( mMapCanvas->mapSettings()->visibleExtent() );
  layoutToPrint->refresh();

  const QString destination = mProject->homePath() + '/' + layoutToPrint->name() + '-' + QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_hhmmss" ) ) + QStringLiteral( ".pdf" );

  QgsLayoutExporter::PdfExportSettings pdfSettings;
  pdfSettings.rasterizeWholeImage = layoutToPrint->customProperty( QStringLiteral( "rasterize" ), false ).toBool();
  pdfSettings.dpi = layoutToPrint->renderContext().dpi();
  pdfSettings.appendGeoreference = true;
  pdfSettings.exportMetadata = true;
  pdfSettings.simplifyGeometries = true;

  QgsLayoutExporter exporter = QgsLayoutExporter( layoutToPrint );
  QgsLayoutExporter::ExportResult result = exporter.exportToPdf( destination, pdfSettings );

  if ( result == QgsLayoutExporter::Success )
    PlatformUtilities::instance()->open( destination );

  return result == QgsLayoutExporter::Success ? true : false;
#else
#warning "No PrintSupport for iOs. QgisMobileapp::print won't do anything."
  return false;
#endif
}

bool QgisMobileapp::printAtlasFeatures( const QString &layoutName, const QList<long long> &featureIds )
{
#ifndef QT_NO_PRINTER
  const QList<QgsPrintLayout *> printLayouts = mProject->layoutManager()->printLayouts();
  QgsPrintLayout *layoutToPrint = nullptr;
  for ( QgsPrintLayout *layout : printLayouts )
  {
    if ( layout->name() == layoutName )
    {
      layoutToPrint = layout;
      break;
    }
  }

  if ( !layoutToPrint || !layoutToPrint->atlas() )
    return false;

  QStringList ids;
  for ( const auto id : featureIds )
  {
    ids << QString::number( id );
  }

  QString error;
  layoutToPrint->atlas()->setFilterExpression( QStringLiteral( "$id IN (%1)" ).arg( ids.join( ',' ) ), error );
  layoutToPrint->atlas()->setFilterFeatures( true );

  const QString destination = mProject->homePath() + '/' + layoutToPrint->name() + QStringLiteral( ".pdf" );

  QgsLayoutExporter::PdfExportSettings pdfSettings;
  pdfSettings.rasterizeWholeImage = layoutToPrint->customProperty( QStringLiteral( "rasterize" ), false ).toBool();
  pdfSettings.dpi = layoutToPrint->renderContext().dpi();
  pdfSettings.appendGeoreference = true;
  pdfSettings.exportMetadata = true;
  pdfSettings.simplifyGeometries = true;

  QVector<double> mapScales = layoutToPrint->project()->viewSettings()->mapScales();
  bool hasProjectScales( layoutToPrint->project()->viewSettings()->useProjectScales() );
  if ( !hasProjectScales || mapScales.isEmpty() )
  {
    // default to global map tool scales
    const QStringList scales = Qgis::defaultProjectScales().split( ',' );
    for ( const QString &scale : scales )
    {
      QStringList parts( scale.split( ':' ) );
      if ( parts.size() == 2 )
      {
        mapScales.push_back( parts[1].toDouble() );
      }
    }
  }
  pdfSettings.predefinedMapScales = mapScales;

  if ( layoutToPrint->atlas()->updateFeatures() )
  {
    QgsLayoutExporter exporter = QgsLayoutExporter( layoutToPrint );
    QgsLayoutExporter::ExportResult result;
    if ( layoutToPrint->customProperty( QStringLiteral( "singleFile" ), true ).toBool() )
    {
      result = exporter.exportToPdf( layoutToPrint->atlas(), destination, pdfSettings, error );
      if ( result == QgsLayoutExporter::Success )
        PlatformUtilities::instance()->open( destination );
    }
    else
    {
      result = exporter.exportToPdfs( layoutToPrint->atlas(), destination, pdfSettings, error );
#ifndef Q_OS_ANDROID
      if ( result == QgsLayoutExporter::Success )
        PlatformUtilities::instance()->open( mProject->homePath() );
#endif
    }
    return result == QgsLayoutExporter::Success ? true : false;
  }

  return false;
#else
#warning "No PrintSupport for iOs. QgisMobileapp::print won't do anything."
  return false;
#endif
}

void QgisMobileapp::setScreenDimmerActive( bool active )
{
  if ( mScreenDimmer )
  {
    mScreenDimmer->setActive( active );
  }
}

bool QgisMobileapp::event( QEvent *event )
{
  if ( event->type() == QEvent::Close )
    QgsApplication::instance()->quit();

  return QQmlApplicationEngine::event( event );
}

QgisMobileapp::~QgisMobileapp()
{
  delete mOfflineEditing;
  mProject->removeAllMapLayers();
  // Reintroduce when created on the heap
  delete mProject;
  delete mAppMissingGridHandler;
}
