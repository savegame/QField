/***************************************************************************
    qfieldcloudutils.cpp
    ---------------------
    begin                : February 2020
    copyright            : (C) 2020 by Mathieu Pellerin
    email                : nirvn dot asia at gmail dot com
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#include "qfieldcloudutils.h"

#include <QDir>
#include <QStandardPaths>
#include <QString>
#include <qgsapplication.h>
#include <qgsmessagelog.h>

static QString sLocalCloudDirectory;

void QFieldCloudUtils::setLocalCloudDirectory( const QString &path )
{
  sLocalCloudDirectory = path;
}

const QString QFieldCloudUtils::localCloudDirectory()
{
  QString cloudDirectoryPath = sLocalCloudDirectory.isNull()
                                 ? QStandardPaths::writableLocation( QStandardPaths::AppDataLocation ) + QStringLiteral( "/cloud_projects" )
                                 : sLocalCloudDirectory;
  return cloudDirectoryPath;
}

const QString QFieldCloudUtils::localProjectFilePath( const QString &username, const QString &projectId )
{
  QString project = QStringLiteral( "%1/%2/%3" ).arg( QFieldCloudUtils::localCloudDirectory(), username, projectId );
  QDir projectDir( project );
  QStringList projectFiles = projectDir.entryList( QStringList() << QStringLiteral( "*.qgz" ) << QStringLiteral( "*.qgs" ) );
  if ( projectFiles.count() > 0 )
  {
    return QStringLiteral( "%1/%2" ).arg( project, projectFiles.at( 0 ) );
  }
  return QString();
}

bool QFieldCloudUtils::isCloudAction( const QgsMapLayer *layer )
{
  Q_ASSERT( layer );

  const QString layerAction( layer->customProperty( QStringLiteral( "QFieldSync/cloud_action" ) ).toString().toUpper() );

  if ( layerAction == QStringLiteral( "NO_ACTION" ) || layerAction == QStringLiteral( "REMOVE" ) )
    return false;
  return true;
}

const QString QFieldCloudUtils::getProjectId( const QString &fileName )
{
  QFileInfo fi( fileName );
  QDir baseDir = fi.isDir() ? fi.canonicalFilePath() : fi.canonicalPath();
  QString basePath = QFileInfo( baseDir.path() ).canonicalFilePath();
  QString cloudPath = QFileInfo( localCloudDirectory() ).canonicalFilePath();

  if ( !cloudPath.isEmpty() && basePath.startsWith( cloudPath ) )
    return baseDir.dirName();

  return QString();
}

void QFieldCloudUtils::setProjectSetting( const QString &projectId, const QString &setting, const QVariant &value )
{
  thread_local QgsSettings settings;
  const QString projectPrefix = QStringLiteral( "QFieldCloud/projects/%1" ).arg( projectId );
  settings.setValue( QStringLiteral( "%1/%2" ).arg( projectPrefix, setting ), value );
}

const QVariant QFieldCloudUtils::projectSetting( const QString &projectId, const QString &setting, const QVariant &defaultValue )
{
  thread_local QgsSettings settings;
  const QString projectPrefix = QStringLiteral( "QFieldCloud/projects/%1" ).arg( projectId );
  return settings.value( QStringLiteral( "%1/%2" ).arg( projectPrefix, setting ), defaultValue );
}
