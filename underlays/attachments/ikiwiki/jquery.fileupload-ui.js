/*
 * jQuery File Upload User Interface Plugin 5.0.13
 * https://github.com/blueimp/jQuery-File-Upload
 *
 * Copyright 2010, Sebastian Tschan
 * https://blueimp.net
 *
 * Licensed under the MIT license:
 * http://creativecommons.org/licenses/MIT/
 */

/*jslint nomen: true, unparam: true, regexp: true */
/*global window, document, URL, webkitURL, FileReader, jQuery */

(function ($) {
    'use strict';
    
    // The UI version extends the basic fileupload widget and adds
    // a complete user interface based on the given upload/download
    // templates.
    $.widget('blueimpUI.fileupload', $.blueimp.fileupload, {
        
        options: {
            // By default, files added to the widget are uploaded as soon
            // as the user clicks on the start buttons. To enable automatic
            // uploads, set the following option to true:
            autoUpload: true,
            // The file upload template that is given as first argument to the
            // jQuery.tmpl method to render the file uploads:
            uploadTemplate: $('#template-upload'),
            // The file download template, that is given as first argument to the
            // jQuery.tmpl method to render the file downloads:
            downloadTemplate: $('#template-download'),
            // The expected data type of the upload response, sets the dataType
            // option of the $.ajax upload requests:
            dataType: 'json',
            
            // The add callback is invoked as soon as files are added to the fileupload
            // widget (via file input selection, drag & drop or add API call).
            // See the basic file upload widget for more information:
            add: function (e, data) {
                var that = $(this).data('fileupload');
                data.isAdjusted = true;
                data.isValidated = that._validate(data.files);
                data.context = that._renderUpload(data.files)
                    .appendTo($(this).find('.files')).fadeIn(function () {
                        // Fix for IE7 and lower:
                        $(this).show();
                    }).data('data', data);
                if ((that.options.autoUpload || data.autoUpload) &&
                        data.isValidated) {
                    data.jqXHR = data.submit();
                }
            },
            // Callback for the start of each file upload request:
            send: function (e, data) {
                if (!data.isValidated) {
                    var that = $(this).data('fileupload');
                    if (!that._validate(data.files)) {
                        return false;
                    }
                }
                if (data.context && data.dataType &&
                        data.dataType.substr(0, 6) === 'iframe') {
                    // Iframe Transport does not support progress events.
                    // In lack of an indeterminate progress bar, we set
                    // the progress to 100%, showing the full animated bar:
                    data.context.find('.ui-progressbar').progressbar(
                        'value',
                        parseInt(100, 10)
                    );
                }
            },
            // Callback for successful uploads:
            done: function (e, data) {
                var that = $(this).data('fileupload');
                if (data.context) {
                    data.context.each(function (index) {
                        var file = ($.isArray(data.result) &&
                                data.result[index]) || {error: 'emptyResult'};
                        $(this).fadeOut(function () {
                            that._renderDownload([file])
                                .css('display', 'none')
                                .replaceAll(this)
                                .fadeIn(function () {
                                    // Fix for IE7 and lower:
                                    $(this).show();
                                });
                        });
                    });
                } else {
                    that._renderDownload(data.result)
                        .css('display', 'none')
                        .appendTo($(this).find('.files'))
                        .fadeIn(function () {
                            // Fix for IE7 and lower:
                            $(this).show();
                        });
                }
            },
            // Callback for failed (abort or error) uploads:
            fail: function (e, data) {
                var that = $(this).data('fileupload');
                if (data.context) {
                    data.context.each(function (index) {
                        $(this).fadeOut(function () {
                            if (data.errorThrown !== 'abort') {
                                var file = data.files[index];
                                file.error = file.error || data.errorThrown
                                    || true;
                                that._renderDownload([file])
                                    .css('display', 'none')
                                    .replaceAll(this)
                                    .fadeIn(function () {
                                        // Fix for IE7 and lower:
                                        $(this).show();
                                    });
                            } else {
                                data.context.remove();
                            }
                        });
                    });
                } else if (data.errorThrown !== 'abort') {
                    data.context = that._renderUpload(data.files)
                        .css('display', 'none')
                        .appendTo($(this).find('.files'))
                        .fadeIn(function () {
                            // Fix for IE7 and lower:
                            $(this).show();
                        }).data('data', data);
                }
            },
            // Callback for upload progress events:
            progress: function (e, data) {
                if (data.context) {
                    data.context.find('.ui-progressbar').progressbar(
                        'value',
                        parseInt(data.loaded / data.total * 100, 10)
                    );
                }
            },
            // Callback for global upload progress events:
            progressall: function (e, data) {
                $(this).find('.fileupload-progressbar').progressbar(
                    'value',
                    parseInt(data.loaded / data.total * 100, 10)
                );
            },
            // Callback for uploads start, equivalent to the global ajaxStart event:
            start: function () {
                $(this).find('.fileupload-progressbar')
                    .progressbar('value', 0).fadeIn();
            },
            // Callback for uploads stop, equivalent to the global ajaxStop event:
            stop: function () {
                $(this).find('.fileupload-progressbar').fadeOut();
            },
        },
	
        _createObjectURL: function (file) {
            var undef = 'undefined',
                urlAPI = (typeof window.createObjectURL !== undef && window) ||
                    (typeof URL !== undef && URL) ||
                    (typeof webkitURL !== undef && webkitURL);
            return urlAPI ? urlAPI.createObjectURL(file) : false;
        },
        
        _revokeObjectURL: function (url) {
            var undef = 'undefined',
                urlAPI = (typeof window.revokeObjectURL !== undef && window) ||
                    (typeof URL !== undef && URL) ||
                    (typeof webkitURL !== undef && webkitURL);
            return urlAPI ? urlAPI.revokeObjectURL(url) : false;
        },

        // Link handler, that allows to download files
        // by drag & drop of the links to the desktop:
        _enableDragToDesktop: function () {
            var link = $(this),
                url = link.prop('href'),
                name = decodeURIComponent(url.split('/').pop())
                    .replace(/:/g, '-'),
                type = 'application/octet-stream';
            link.bind('dragstart', function (e) {
                try {
                    e.originalEvent.dataTransfer.setData(
                        'DownloadURL',
                        [type, name, url].join(':')
                    );
                } catch (err) {}
            });
        },

        _hasError: function (file) {
            if (file.error) {
                return file.error;
            }
            return null;
        },

        _validate: function (files) {
            var that = this,
                valid;
            $.each(files, function (index, file) {
                file.error = that._hasError(file);
                valid = !file.error;
            });
            return valid;
        },

        _uploadTemplateHelper: function (file) {
            return file;
        },

        _renderUploadTemplate: function (files) {
            var that = this;
            return $.tmpl(
                this.options.uploadTemplate,
                $.map(files, function (file) {
                    return that._uploadTemplateHelper(file);
                })
            );
        },

        _renderUpload: function (files) {
            var that = this,
                options = this.options,
                tmpl = this._renderUploadTemplate(files);
            if (!(tmpl instanceof $)) {
                return $();
            }
            tmpl.css('display', 'none');
            // .slice(1).remove().end().first() removes all but the first
            // element and selects only the first for the jQuery collection:
            tmpl.find('.progress div').slice(1).remove().end().first()
                .progressbar();
            tmpl.find('.start button').slice(
                this.options.autoUpload ? 0 : 1
            ).remove().end().first()
                .button({
                    text: false,
                    icons: {primary: 'ui-icon-circle-arrow-e'}
                });
            tmpl.find('.cancel button').slice(1).remove().end().first()
                .button({
                    text: false,
                    icons: {primary: 'ui-icon-cancel'}
                });
            return tmpl;
        },

        _downloadTemplateHelper: function (file) {
            return file;
        },

        _renderDownloadTemplate: function (files) {
            var that = this;
            return $.tmpl(
                this.options.downloadTemplate,
                $.map(files, function (file) {
                    return that._downloadTemplateHelper(file);
                })
            );
        },
        
        _renderDownload: function (files) {
            var tmpl = this._renderDownloadTemplate(files);
            if (!(tmpl instanceof $)) {
                return $();
            }
            tmpl.css('display', 'none');
            tmpl.find('a').each(this._enableDragToDesktop);
            return tmpl;
        },
        
        _startHandler: function (e) {
            e.preventDefault();
            var tmpl = $(this).closest('.template-upload'),
                data = tmpl.data('data');
            if (data && data.submit && !data.jqXHR) {
                data.jqXHR = data.submit();
                $(this).fadeOut();
            }
        },
        
        _cancelHandler: function (e) {
            e.preventDefault();
            var tmpl = $(this).closest('.template-upload'),
                data = tmpl.data('data') || {};
            if (!data.jqXHR) {
                data.errorThrown = 'abort';
                e.data.fileupload._trigger('fail', e, data);
            } else {
                data.jqXHR.abort();
            }
        },
        
        _initEventHandlers: function () {
            $.blueimp.fileupload.prototype._initEventHandlers.call(this);
            var filesList = this.element.find('.files'),
                eventData = {fileupload: this};
            filesList.find('.start button')
                .live(
                    'click.' + this.options.namespace,
                    eventData,
                    this._startHandler
                );
            filesList.find('.cancel button')
                .live(
                    'click.' + this.options.namespace,
                    eventData,
                    this._cancelHandler
                );
        },
        
        _destroyEventHandlers: function () {
            var filesList = this.element.find('.files');
            filesList.find('.start button')
                .die('click.' + this.options.namespace);
            filesList.find('.cancel button')
                .die('click.' + this.options.namespace);
            $.blueimp.fileupload.prototype._destroyEventHandlers.call(this);
        },

        _initTemplates: function () {
            // Handle cases where the templates are defined
            // after the widget library has been included:
            if (this.options.uploadTemplate instanceof $ &&
                    !this.options.uploadTemplate.length) {
                this.options.uploadTemplate = $(
                    this.options.uploadTemplate.selector
                );
            }
            if (this.options.downloadTemplate instanceof $ &&
                    !this.options.downloadTemplate.length) {
                this.options.downloadTemplate = $(
                    this.options.downloadTemplate.selector
                );
            }
        },

        _create: function () {
            $.blueimp.fileupload.prototype._create.call(this);
            this._initTemplates();
        },
        
        enable: function () {
            $.blueimp.fileupload.prototype.enable.call(this);
        },
        
        disable: function () {
            $.blueimp.fileupload.prototype.disable.call(this);
        }

    });

}(jQuery));
