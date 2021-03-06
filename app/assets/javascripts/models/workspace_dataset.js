chorus.models.WorkspaceDataset = chorus.models.Dataset.extend({
    constructorName: "WorkspaceDataset",

    urlTemplate: function(options) {
        options = options || {};
        if(options.download) {
            return this._super("urlTemplate", arguments);
        } else if(this.isChorusView() &&
            (_.indexOf(["create", "update", "delete"], options.method) > -1)) {
            return "chorus_views/{{id}}";
        } else {
            return "workspaces/{{workspace.id}}/datasets/{{id}}";
        }
    },

    showUrlTemplate: function() {
        var resource = this.isChorusView() ? "chorus_views" : "datasets";
        return "workspaces/{{workspace.id}}/" + resource + "/{{id}}";
    },

    isChorusView: function() {
        return this.get("entitySubtype") === "CHORUS_VIEW";
    },

    iconUrl: function() {
        var result = this._super("iconUrl", arguments);
        if (this.get('hasCredentials') === false) {
            result = result.replace(".png", "_locked.png");
        }
        return result;
    },

    query: function() {
        return this.get("query") || this.get("content");
    },

    isSandbox: function() {
        return this.get("entitySubtype") === "SANDBOX_TABLE";
    },

    deriveChorusView: function() {
        var chorusView = new chorus.models.ChorusView({
            sourceObjectId: this.id,
            sourceObjectType: "dataset",
            workspace: this.get("workspace"),
            objectName: this.name()
        });
        chorusView.setSchema(this.schema());
        chorusView.sourceObject = this;
        return chorusView;
    },

    createDuplicateChorusView: function() {
        var attrs = _.extend({},  this.attributes, {
            objectName: t("dataset.chorusview.copy_name", { name: this.get("objectName") }),
            sourceObjectId: this.id
        });
        delete attrs.id;
        var chorusView = new chorus.models.ChorusView(attrs);
        chorusView.duplicate = true;
        chorusView.sourceObject = this;
        return chorusView;
    },

    statistics: function() {
        var stats = this._super("statistics");

        if (this.isChorusView() && !stats.datasetId) {
            stats.set({ workspace: this.get("workspace")});
            stats.datasetId = this.get("id");
        }

        return stats;
    },

    getImports: function() {
        if (!this._datasetImports) {
            this._datasetImports = new chorus.collections.WorkspaceImportSet([], {
                datasetId: this.get("id"),
                workspaceId: this.get("workspace").id
            });
        }
        return this._datasetImports;
    },

    getImportSchedules: function() {
        if (!this._datasetImportSchedules) {
            this._datasetImportSchedules = new chorus.collections.DatasetImportScheduleSet([], {
                datasetId: this.get("id"),
                workspaceId: this.get("workspace").id
            });
            this._datasetImportSchedules.on("remove", this.importScheduleRemoved, this);
        }
        return this._datasetImportSchedules;
    },

    importScheduleRemoved: function() {
        this.unset("frequency", {silent: true});
        this.trigger('change');
    },

    importSchedule: function() {
        return this.getImportSchedules().last();
    },

    lastImport: function() {
        if(this.hasImport())
        {
            return this.getImports().first();
        }
    },

    setImport: function(datasetImport) {
        this._datasetImport = datasetImport;
    },

    importFrequency: function() {
        if (this.importSchedule()) {
            return this.importSchedule().get('frequency');
        } else {
            return this.get('frequency');
        }
    },

    columns: function(options) {
        var result = this._super('columns', arguments);
        result.attributes.workspaceId = this.get("workspace").id;
        return result;
    },

    hasOwnPage: function() {
        return true;
    },

    lastImportSource: function() {
        var importInfo = this.get("importInfo");
        if (importInfo && importInfo.sourceId) {
            return new chorus.models.WorkspaceDataset({
                id: importInfo.sourceId,
                objectName: importInfo.sourceTable,
                workspaceId: this.get("workspace").id
            });
        }
    },

    canBeImportSource: function() {
        return !this.isSandbox();
    },

    canBeImportDestination: function() {
        return true;
    },

    setWorkspace: function(workspace) {
        this.set({workspace: {id: workspace.id}});
    },

    activities: function() {
        var original = this._super("activities", arguments);
        if (this.isChorusView()) {
            original.attributes.workspace = this.get("workspace");
        }

        return original;
    }
});
