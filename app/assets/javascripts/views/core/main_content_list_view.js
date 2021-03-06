chorus.views.MainContentList = chorus.views.MainContentView.extend({
    setup: function(options) {
        var modelClass = options.modelClass;
        var collection = this.collection;

        if(options.checkable) {
            this.content = new chorus.views.CheckableList(_.extend({
                    collection: collection,
                    entityType: modelClass.toLowerCase(),
                    entityViewType: chorus.views[modelClass]
                },
                options.contentOptions));
        } else {
            this.content = new chorus.views[modelClass + "List"](_.extend({collection: collection}, options.contentOptions));
        }

        this.contentHeader = options.contentHeader || new chorus.views.ListHeaderView({title: options.title || (!options.emptyTitleBeforeFetch && (modelClass + "s")), linkMenus: options.linkMenus, imageUrl: options.imageUrl, sandbox: options.sandbox});

        if (options.hasOwnProperty('persistent')) {
            this.persistent = options.persistent;
        }

        this.suppressRenderOnChange = true;

        if (options.contentDetails) {
            this.contentDetails = options.contentDetails;
        } else {
            this.contentDetails = new chorus.views.ListContentDetails(
                _.extend({
                    collection: collection,
                    modelClass: modelClass,
                    buttons: options.buttons,
                    search: options.search && _.extend({list: $(this.content.el)}, options.search)
                }, options.contentDetailsOptions));

            this.contentFooter = new chorus.views.ListContentDetails({
                collection: collection,
                modelClass: modelClass,
                hideCounts: true,
                hideIfNoPagination: true
            });
        }
    },

    additionalClass: "main_content_list"
});
