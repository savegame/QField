/***************************************************************************
 abstractgnssreceiver.h - AbstractGnssReceiver

 ---------------------
 begin                : 22.05.2022
 copyright            : (C) 2022 by Mathieu Pellerin
 email                : mathieu at opengis dot ch
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/
#ifndef ABSTRACTGNSSRECEIVER_H
#define ABSTRACTGNSSRECEIVER_H

#include "gnsspositioninformation.h"

#include <QAbstractSocket>
#include <QObject>

class AbstractGnssReceiver : public QObject
{
    Q_OBJECT

    Q_PROPERTY( GnssPositionInformation lastGnssPositionInformation READ lastGnssPositionInformation NOTIFY lastGnssPositionInformationChanged )
    Q_PROPERTY( QAbstractSocket::SocketState socketState READ socketState NOTIFY socketStateChanged )
    Q_PROPERTY( QString socketStateString READ socketStateString NOTIFY socketStateStringChanged )

  public:
    explicit AbstractGnssReceiver( QObject *parent = nullptr )
      : QObject( parent ) {}
    virtual ~AbstractGnssReceiver() = default;

    bool valid() const { return mValid; }
    void setValid( bool valid ) { mValid = valid; }

    void connectDevice() { handleConnectDevice(); }
    void disconnectDevice() { handleDisconnectDevice(); }

    GnssPositionInformation lastGnssPositionInformation() const { return mLastGnssPositionInformation; }
    QAbstractSocket::SocketState socketState() const { return mSocketState; }
    QString socketStateString() const { return mSocketStateString; }

  signals:
    void validChanged();
    void lastGnssPositionInformationChanged( GnssPositionInformation &lastGnssPositionInformation );
    void socketStateChanged( QAbstractSocket::SocketState socketState );
    void socketStateStringChanged( QString socketStateString );

  private:
    friend class BluetoothReceiver;
    friend class InternalGnssReceiver;

    virtual void handleConnectDevice() {}
    virtual void handleDisconnectDevice() {}

    bool mValid = false;
    GnssPositionInformation mLastGnssPositionInformation;
    QAbstractSocket::SocketState mSocketState;
    QString mSocketStateString;
};

#endif // ABSTRACTGNSSRECEIVER_H
