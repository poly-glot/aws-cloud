function handler(event) {
    var request = event.request;
    var uri = request.uri;

    if (uri.indexOf('/api/') === 0) {
        request.uri = uri.substring(4);
        return request;
    }

    var last = uri.split('/').pop();
    if (last.indexOf('.') === -1) {
        request.uri = '/index.html';
    }
    return request;
}
