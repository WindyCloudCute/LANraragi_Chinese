// Scripting for the Upload page.
const Upload = {};

let processingArchives = 0;
let completedArchives = 0;
let failedArchives = 0;
let totalUploads = 0;

// Set up jqueryfileupload.
Upload.initializeAll = function () {
    // bind events to DOM
    $(document).on("click.download-url", "#download-url", Upload.downloadUrl);
    $(document).on("click.return", "#return", () => { window.location.href = "/"; });

    $("#fileupload").fileupload({
        dataType: "json",
        formData() {
            const array = [{ name: "catid", value: document.getElementById("category").value }];
            return array;
        },
        done(e, data) {
            let result;
            if (data.result.success === 0) {
                result = `<tr><td>${data.result.name}</td>
                              <td><i class='fa fa-exclamation-circle' style='margin-left:20px; margin-right: 10px; color: red'></i>${data.result.error}</td>
                          </tr>`;
            } else {
                result = `<tr><td style="max-width:200px; overflow:hidden; text-overflow:ellipsis;">
                                <a href="#" id="${data.result.job}-name" title="${data.result.name}">${data.result.name}</a>
                              </td>
                              <td><i id="${data.result.job}-icon" class='fa fa-spinner fa-spin' style='margin-left:20px; margin-right: 10px;'></i>
                                <a href="#" id="${data.result.job}-link">处理文件... (Job #${data.result.job})</a>
                              </td>
                          </tr>`;
            }

            $("#progress .bar").css("width", "0%");
            $("#files").append(result);

            totalUploads += 1;
            processingArchives += 1;
            Upload.updateUploadCounters();

            // Check minion job state periodically to update the result
            Server.checkJobStatus(
                data.result.job,
                true,
                (d) => Upload.handleCompletedUpload(data.result.job, d),
                (error) => Upload.handleFailedUpload(data.result.job, error),
            );
        },

        fail(e, data) {
            const result = `<tr><td>${data.result.name}</td>
                              <td><i class='fa fa-exclamation-circle' style='margin-left:20px; margin-right: 10px; color: red'></i>${data.errorThrown}</td>
                          </tr>`;
            $("#progress .bar").css("width", "0%");
            $("#files").append(result);

            totalUploads += 1;
            failedArchives += 1;
            Upload.updateUploadCounters();
        },

        progressall(e, data) {
            const progress = parseInt((data.loaded / data.total) * 100, 10);
            $("#progress .bar").css("width", `${progress}%`);
        },

    });
};

// Handle updating the upload counters.
Upload.updateUploadCounters = function () {
    $("#progressCount").html(`🤔 处理中: ${processingArchives} 🙌 完成: ${completedArchives} 👹 失败: ${failedArchives}`);

    let icon;
    if (completedArchives === totalUploads) {
        icon = "fas fa-check-circle";
    } else if (failedArchives > 0) {
        icon = "fas fa-exclamation-circle";
    } else {
        icon = "fa fa-spinner fa-spin";
    }
    $("#progressTotal").html(`<i class="${icon}"></i> 共计:${completedArchives + failedArchives}/${totalUploads}`);

    // At the end of the upload job, dump the search cache!
    if (processingArchives === 0) { Server.invalidateCache(); }
};

// Handle a completed job from minion.
// Update the line in upload results with the title, ID, message.
Upload.handleCompletedUpload = function (jobID, d) {
    $(`#${jobID}-name`).html(d.result.title);

    if (d.result.id) {
        $(`#${jobID}-name`).attr("href", `reader?id=${d.result.id}`);
        $(`#${jobID}-link`).attr("href", `edit?id=${d.result.id}`);
    }

    if (d.result.success) {
        $(`#${jobID}-link`).html(`点击此处编辑元数据.<br>(${d.result.message})`);
        $(`#${jobID}-icon`).attr("class", "fa fa-check-circle");
        completedArchives += 1;
    } else {
        $(`#${jobID}-link`).html(`处理档案时发生错误.<br>(${d.result.message})`);
        $(`#${jobID}-icon`).attr("class", "fa fa-exclamation-circle");
        failedArchives += 1;
    }

    processingArchives -= 1;
    Upload.updateUploadCounters();
};

Upload.handleFailedUpload = function (jobID, d) {
    $(`#${jobID}-link`).html(`处理文件时出错.<br>(${d})`);
    $(`#${jobID}-icon`).attr("class", "fa fa-exclamation-circle");

    failedArchives += 1;
    processingArchives -= 1;
    Upload.updateUploadCounters();
};

// Send URLs to the Download API and add a Server.checkJobStatus to track its progress.
Upload.downloadUrl = function () {
    const categoryID = document.getElementById("category").value;

    // One fetch job per non-empty line of the form
    $("#urlForm").val().split(/\r|\n/).forEach((url) => {
        if (url === "") return;

        const formData = new FormData();
        formData.append("url", url);

        if (categoryID !== "") {
            formData.append("catid", categoryID);
        }

        fetch("/api/download_url", {
            method: "POST",
            body: formData,
        })
            .then((response) => response.json())
            .then((data) => {
                if (data.success) {
                    const result = `<tr><td style="max-width:200px; overflow:hidden; text-overflow:ellipsis;">
                                    <a href="#" id="${data.job}-name" title="${data.url}">${data.url}</a>
                                </td>
                                <td><i id="${data.job}-icon" class='fa fa-spinner fa-spin' style='margin-left:20px; margin-right: 10px;'></i>
                                <a href="#" id="${data.job}-link">下载文件... (Job #${data.job})</a>
                                </td>
                            </tr>`;

                    $("#files").append(result);

                    totalUploads += 1;
                    processingArchives += 1;
                    Upload.updateUploadCounters();

                    // Check minion job state periodically to update the result
                    Server.checkJobStatus(
                        data.job,
                        true,
                        (d) => Upload.handleCompletedUpload(data.job, d),
                        (error) => Upload.handleFailedUpload(data.job, error),
                    );
                } else {
                    throw new Error(data.message);
                }
            })
            .catch((error) => LRR.showErrorToast("添加下载作业时出错", error));
    });
};

jQuery(() => {
    Upload.initializeAll();
});
