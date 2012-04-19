chorus.views.WorkfileContentDetails = chorus.views.Base.extend({
    templateName:"workfile_content_details",
    additionalClass: "workfile_content_details",

    setup:function () {
        chorus.PageEvents.subscribe("file:autosaved", this.updateAutosaveText, this);
    },

    updateAutosaveText:function (args) {
        var text = args ? args : "workfile.content_details.auto_save";

        var time = this.formatTime(new Date());
        this.$("span.auto_save").removeClass("hidden");
        this.$("span.auto_save").text(t(text, {time:time}))
    },

    additionalContext: function() {
        return {
            isLatestVersion: this.model.isLatestVersion()
        }
    },

    postRender:function () {
        var self = this;
        chorus.menu(this.$('.save_as'), {
            content:this.$(".save_options").html(),
            orientation:"left",
            contentEvents:{
                '.save_as_current':_.bind(this.replaceCurrentVersion, this),
                '.save_as_new':_.bind(this.workfileNewVersion, this)
            }
        });

        if (!this.model.workspace().isActive()) {
            this.$(".save_as").attr("disabled", "disabled");
        }
    },

    replaceCurrentVersion:function () {
        chorus.PageEvents.broadcast("file:saveCurrent");
        this.updateAutosaveText("workfile.content_details.save");
    },

    workfileNewVersion:function () {
        chorus.PageEvents.broadcast("file:createWorkfileNewVersion");
    },

    formatTime:function (time) {
        var hours = time.getHours();
        var minutes = time.getMinutes();

        var suffix = "AM";
        if (hours >= 12) {
            suffix = "PM";
            hours = hours - 12;
        }
        if (hours == 0) {
            hours = 12;
        }
        if (minutes < 10) {
            minutes = "0" + minutes;
        }
        return hours + ":" + minutes + " " + suffix;
    }
},
{
    buildFor:function (model, contentView) {
        if (model.isImage()) {
            return new chorus.views.ImageWorkfileContentDetails({ model:model });
        }

        if (model.isSql()) {
            if (model.workspace().isActive()) {
                return new chorus.views.SqlWorkfileContentDetails({ model:model, contentView: contentView });
            } else {
                return new chorus.views.ArchivedWorkfileContentDetails({ model:model });
            }
        }

        if (model.isAlpine()) {
            return new chorus.views.AlpineWorkfileContentDetails({ model:model });
        }

        if (model.isBinary()) {
            return new chorus.views.BinaryWorkfileContentDetails({ model:model });
        }

        return new chorus.views.WorkfileContentDetails({ model:model });
    }
});
