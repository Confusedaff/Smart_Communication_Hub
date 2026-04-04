#include "ApiClient.h"
#include <QNetworkRequest>
#include <QHttpMultiPart>
#include <QJsonDocument>
#include <QJsonArray>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QUrl>
#include <functional>

ApiClient::ApiClient(const QString& baseUrl, QObject* parent)
    : QObject(parent), m_baseUrl(baseUrl)
{
    m_nam = new QNetworkAccessManager(this);
}

void ApiClient::setBaseUrl(const QString& url) {
    m_baseUrl = url;
}

QNetworkRequest ApiClient::makeRequest(const QString& path) {
    QNetworkRequest req(QUrl(m_baseUrl + path));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    return req;
}

void ApiClient::handleReply(
    QNetworkReply* reply,
    std::function<void(const QJsonObject&)> onSuccess,
    std::function<void(const QString&)> onError)
{
    connect(reply, &QNetworkReply::finished, this, [reply, onSuccess, onError]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            QString errMsg = reply->errorString();
            // Try to get body for details
            QByteArray body = reply->readAll();
            QJsonDocument doc = QJsonDocument::fromJson(body);
            if (doc.isObject() && doc.object().contains("detail")) {
                errMsg = doc.object()["detail"].toString();
            }
            onError(errMsg);
            return;
        }
        QByteArray data = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isObject()) {
            onSuccess(doc.object());
        } else {
            onError("Invalid JSON response");
        }
    });
}

void ApiClient::checkHealth() {
    auto* reply = m_nam->get(makeRequest("/health"));
    handleReply(reply,
        [this](const QJsonObject& obj) { emit healthCheckDone(true, obj); },
        [this](const QString& err)     { emit healthCheckDone(false, {}); }
    );
}

void ApiClient::uploadTranscript(const QString& filePath) {
    QFile* file = new QFile(filePath);
    if (!file->open(QIODevice::ReadOnly)) {
        delete file;
        emit uploadError("Cannot open file: " + filePath);
        return;
    }

    QHttpMultiPart* multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
    QHttpPart filePart;
    QString filename = QFileInfo(filePath).fileName();
    filePart.setHeader(QNetworkRequest::ContentDispositionHeader,
        QString("form-data; name=\"file\"; filename=\"%1\"").arg(filename));

    QMimeDatabase mimeDb;
    QMimeType mime = mimeDb.mimeTypeForFile(filePath);
    filePart.setHeader(QNetworkRequest::ContentTypeHeader, mime.name());
    filePart.setBodyDevice(file);
    file->setParent(multiPart);
    multiPart->append(filePart);

    QNetworkRequest req(QUrl(m_baseUrl + "/upload"));
    auto* reply = m_nam->post(req, multiPart);
    multiPart->setParent(reply);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        QByteArray data = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(data);

        if (reply->error() != QNetworkReply::NoError || !doc.isObject()) {
            QString errMsg = reply->errorString();
            if (doc.isObject() && doc.object().contains("detail"))
                errMsg = doc.object()["detail"].toString();
            emit uploadError(errMsg);
            return;
        }
        QJsonObject obj = doc.object();
        emit uploadDone(obj["session_id"].toString(), obj);
    });
}

void ApiClient::extractFromSession(const QString& sessionId, bool force, const QString& engine) {
    QString path = "/sessions/" + sessionId + "/extract";
    QStringList params;
    if (force)        params << "force=true";
    if (!engine.isEmpty()) params << "engine=" + engine;
    if (!params.isEmpty()) path += "?" + params.join("&");

    auto* reply = m_nam->get(makeRequest(path));
    handleReply(reply,
        [this](const QJsonObject& obj) { emit extractDone(obj); },
        [this](const QString& err)     { emit extractError(err); }
    );
}

void ApiClient::sendChat(const QString& sessionId, const QString& question) {
    QJsonObject body;
    body["question"] = question;
    QByteArray jsonData = QJsonDocument(body).toJson();

    QNetworkRequest req = makeRequest("/sessions/" + sessionId + "/chat");
    auto* reply = m_nam->post(req, jsonData);
    handleReply(reply,
        [this](const QJsonObject& obj) { emit chatDone(obj); },
        [this](const QString& err)     { emit chatError(err); }
    );
}

void ApiClient::getChatHistory(const QString& sessionId) {
    auto* reply = m_nam->get(makeRequest("/sessions/" + sessionId + "/chat/history"));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        QByteArray data = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isObject() && doc.object().contains("history")) {
            emit chatHistoryDone(doc.object()["history"].toArray());
        }
    });
}

void ApiClient::clearChatHistory(const QString& sessionId) {
    QNetworkRequest req = makeRequest("/sessions/" + sessionId + "/chat/history");
    auto* reply = m_nam->sendCustomRequest(req, "DELETE");
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        emit chatHistoryCleared();
    });
}

void ApiClient::getTranscript(const QString& sessionId) {
    auto* reply = m_nam->get(makeRequest("/sessions/" + sessionId + "/transcript?format=segments"));
    handleReply(reply,
        [this](const QJsonObject& obj) { emit transcriptDone(obj); },
        [this](const QString& err) { Q_UNUSED(err); }
    );
}

void ApiClient::getTimingStatus(const QString& task) {
    auto* reply = m_nam->get(makeRequest("/timing/status?task=" + task));
    handleReply(reply,
        [this](const QJsonObject& obj) { emit timingDone(obj); },
        [this](const QString& err) { Q_UNUSED(err); }
    );
}

void ApiClient::deleteSession(const QString& sessionId) {
    QNetworkRequest req = makeRequest("/sessions/" + sessionId);
    auto* reply = m_nam->sendCustomRequest(req, "DELETE");
    connect(reply, &QNetworkReply::finished, this, [this, reply, sessionId]() {
        reply->deleteLater();
        emit sessionDeleted(sessionId);
    });
}

QUrl ApiClient::csvExportUrl(const QString& sessionId) const {
    return QUrl(m_baseUrl + "/sessions/" + sessionId + "/export/csv");
}
QUrl ApiClient::pdfExportUrl(const QString& sessionId) const {
    return QUrl(m_baseUrl + "/sessions/" + sessionId + "/export/pdf");
}

void ApiClient::downloadCsv(const QString& sessionId, const QString& savePath) {
    auto* reply = m_nam->get(QNetworkRequest(csvExportUrl(sessionId)));
    connect(reply, &QNetworkReply::finished, this, [this, reply, savePath]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit downloadError(reply->errorString()); return;
        }
        QFile file(savePath);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(reply->readAll());
            emit downloadDone(savePath);
        } else {
            emit downloadError("Cannot write file");
        }
    });
}

void ApiClient::downloadPdf(const QString& sessionId, const QString& savePath) {
    auto* reply = m_nam->get(QNetworkRequest(pdfExportUrl(sessionId)));
    connect(reply, &QNetworkReply::finished, this, [this, reply, savePath]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit downloadError(reply->errorString()); return;
        }
        QFile file(savePath);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(reply->readAll());
            emit downloadDone(savePath);
        } else {
            emit downloadError("Cannot write file");
        }
    });
}