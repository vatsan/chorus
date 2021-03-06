(function() {
    var CLASS_MAP = {
        "actor": "User",
        "dataset": "WorkspaceDataset",
        'dataSource': 'DynamicDataSource',
        "gnipDataSource": "GnipDataSource",
        "newOwner": "User",
        "hdfsDataSource": "HdfsDataSource",
        "workfile": "Workfile",
        "workspace": "Workspace",
        "newUser" : "User",
        "noteObject" : "NoteObject",
        "hdfsEntry" : "HdfsEntry",
        "member": "User",
        "sourceDataset": "WorkspaceDataset",
        "schema": "Schema"
    };

    function makeAssociationMethod(associate, setupFunction) {
        return function() {
            var className = CLASS_MAP[associate];
            var modelClass = chorus.models[className];
            var model = new modelClass(this.get(associate));
            if (setupFunction) setupFunction.call(this, model);
            return model;
        };
    }

    chorus.models.Activity = chorus.models.Base.extend({
        constructorName: "Activity",
        urlTemplate: "activities/{{id}}",

        author: function() {
            if (!this._author) {
                if (this.has("author")) {
                    this._author = new chorus.models.User(this.get("author"));
                } else if (this.has("actor")) {
                    this._author = new chorus.models.User(this.get("actor"));
                }
            }

            return this._author;
        },

        newOwner: makeAssociationMethod("newOwner"),
        workspace: makeAssociationMethod("workspace"),
        schema: makeAssociationMethod("schema"),
        actor: makeAssociationMethod("actor"),
        dataSource: makeAssociationMethod('dataSource'),
        gnipDataSource: makeAssociationMethod("gnipDataSource"),
        hdfsDataSource: makeAssociationMethod("hdfsDataSource"),
        workfile: makeAssociationMethod("workfile"),
        newUser: makeAssociationMethod("newUser"),
        member: makeAssociationMethod("member"),

        dataset: makeAssociationMethod("dataset", function(model) {
            model.set({workspace: this.get("workspace")}, {silent: true});
        }),

        importSource: makeAssociationMethod("sourceDataset", function(model) {
            model.set({workspace: this.get("workspace")}, {silent: true});
        }),

        hdfsEntry: makeAssociationMethod("hdfsEntry", function(model) {
            var hdfsEntry = this.get("hdfsEntry");
            model.set({
                id : hdfsEntry.id,
                hdfsDataSource: hdfsEntry.hdfsDataSource
            });
        }),

        noteObject: function() {
            var model;

            switch (this.get("actionType")) {
                case "NoteOnHdfsDataSource":
                    model = new chorus.models.HdfsDataSource();
                    model.set(this.get("hdfsDataSource"));
                    break;
                case "NoteOnDataSource":
                    model = new chorus.models.DynamicDataSource(this.get("dataSource"));
                    break;
                case "NoteOnGnipDataSource":
                    model = new chorus.models.GnipDataSource();
                    model.set(this.get("gnipDataSource"));
                    break;
                case "NoteOnHdfsFile":
                    model = new chorus.models.HdfsEntry();
                    model.set({
                        hdfsDataSource: new chorus.models.HdfsDataSource(this.get("hdfsFile").hdfsDataSource),
                        id: this.get("hdfsFile").id,
                        name: this.get("hdfsFile").name
                    });
                    break;
                case "NoteOnWorkspace":
                    model = new chorus.models.Workspace();
                    model.set(this.get("workspace"));
                    break;
                case "NoteOnDataset":
                    model = new chorus.models.Dataset();
                    model.set(this.get("dataset"));
                    break;
                case "NoteOnWorkspaceDataset":
                    model = new chorus.models.WorkspaceDataset();
                    model.set(this.get("dataset"));
                    model.setWorkspace(this.get("workspace"));
                    break;
                case "NoteOnWorkfile":
                    model = new chorus.models.Workfile();
                    model.set(this.get("workfile"));
                    break;
            }
            return model;
        },

        comments: function() {
            this._comments || (this._comments = new chorus.collections.CommentSet(
                this.get("comments"), {
                    entityType: this.collection && this.collection.attributes.entityType,
                    entityId: this.collection && this.collection.attributes.entityId
                }
            ));
            return this._comments;
        },

        promoteToInsight: function(options) {
            var insight = new chorus.models.Insight({
                noteId: this.get("id"),
                action: "create"
            });
            insight.bind("saved", function() {
                this.fetch();
                if (options && options.success) {
                    options.success(this);
                }
            }, this);

            insight.save({ validateBody: false });
        },

        publish: function() {
            var insight = new chorus.models.Insight({
                noteId: this.get("id"),
                action: "publish"
            });

            insight.bind("saved", function() {
                this.fetch();
            }, this);

            insight.save({ validateBody: false }, {method: 'create'});
        },

        unpublish: function() {
            var insight = new chorus.models.Insight({
                noteId: this.get("id"),
                action: "unpublish"
            });

            insight.bind("saved", function() {
                this.fetch();
            }, this);

            insight.save({ validateBody: false }, {method: 'create'});
        },

        toNote: function() {
            var comment = new chorus.models.Note({
                id: this.id,
                body: this.get("body")
            });

            return comment;
        },

        attachments: function() {
            if (!this._attachments) {
                this._attachments = _.map(this.get("attachments"), function(artifactJson) {
                    var klass;
                    switch (artifactJson.entityType) {
                        case 'workfile':
                            klass = chorus.models.DynamicWorkfile;
                            break;
                        case 'dataset':
                            klass = chorus.models.WorkspaceDataset;
                            break;
                        default:
                            klass = chorus.models.Attachment;
                            break;
                    }
                    return new klass(artifactJson);
                });
            }
            return this._attachments;
        },

        isNote: function() {
            return this.get("action") === "NOTE";
        },

        canBePromotedToInsight: function() {
            return this.isNote() && !this.isInsight();
        },

        isInsight: function() {
            return this.get("isInsight");
        },

        isSubComment: function() {
            return this.get("action") === "SUB_COMMENT";
        },

        hasCommitMessage: function() {
            return (this.get("action") === "WorkfileUpgradedVersion" ||
                this.get("action") === "WorkfileCreated" ) &&
                this.get("commitMessage");
        },

        isUserGenerated: function () {
            return this.isNote() || this.isInsight() || this.isSubComment();
        },

        isPublished: function() {
            return this.get("isPublished");
        },

        isOwner: function() {
            return (this.actor().id === chorus.session.user().id);
        },

        isFailure: function() {
            var failureActions = [
                "GnipStreamImportFailed",
                "FileImportFailed",
                "WorkspaceImportFailed",
                "SchemaImportFailed"
            ];

            return _.contains(failureActions, this.get("action"));
        },

        isSuccessfulImport: function() {
            var successActions = [
                "GnipStreamImportSuccess",
                "FileImportSuccess",
                "WorkspaceImportSuccess",
                "SchemaImportSuccess"
            ];

            return _.contains(successActions, this.get("action"));
        },

        promoterLink: function() {
            var promoter = this.promoter();
            return promoter ? Handlebars.helpers.userProfileLink(promoter) : "MISSING PROMOTER";
        },

        promoter: function () {
            return this.get("promotedBy") ? new chorus.models.User(this.get("promotedBy")) : null;
        },

        promotionTimestamp:function() {
            return this.get("promotionTime") ? Handlebars.helpers.relativeTimestamp(this.get("promotionTime")) : null;
        },

        reindexError: function() {
            if (this.isFailure()) {
                this.attributes['errorModelId'] = this.get("id");
            }
        }
    });
})();
