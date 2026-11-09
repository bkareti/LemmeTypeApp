import Foundation

/// A `multipart/form-data` body with text fields and one audio file, for
/// providers that take an upload.
struct CloudMultipartForm {
    let boundary: String
    let fields: [(name: String, value: String)]
    let fileField: String
    let fileName: String
    let fileType: String
    let file: Data

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    var body: Data {
        var data = Data(capacity: file.count + 512)
        for field in fields {
            data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n".utf8))
            data.append(Data("\(field.value)\r\n".utf8))
        }
        data.append(
            Data(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n"
                    .utf8))
        data.append(Data("Content-Type: \(fileType)\r\n\r\n".utf8))
        data.append(file)
        data.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return data
    }
}
