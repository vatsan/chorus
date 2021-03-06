describe("chorus.views.DatasetList", function() {
    beforeEach(function() {
        this.collection = new chorus.collections.SchemaDatasetSet([
            rspecFixtures.workspaceDataset.chorusView({ hasCredentials: true, objectName: "foo" }),
            rspecFixtures.workspaceDataset.datasetTable({ hasCredentials: true, objectName: "bar" }),
            rspecFixtures.workspaceDataset.datasetTable({ objectName: "baz" })
        ], { instanceId: "1", databaseName: "two", schemaName: "three" });
        this.collection.loaded = true;

        this.view = new chorus.views.DatasetList({
            collection: this.collection,
            activeWorkspace: true,
            checkable: true
        });
        this.view.render();
    });

    itBehavesLike.CheckableList();

    it("does not re-render when a dataset is updated", function() {
        spyOn(this.view, "preRender");
        this.collection.at(0).trigger("change");
        expect(this.view.preRender).not.toHaveBeenCalled();
    });

    context("when the checkable flag is falsy", function() {
        beforeEach(function() {
            this.view = new chorus.views.DatasetList({ collection: this.collection });
        });

        it("does not render checkboxes", function() {
            expect(this.view.$("input[type=checkbox]")).not.toExist();
        });
    });

    describe("when there are no datasets", function() {
        beforeEach(function() {
            this.view.collection = new chorus.collections.SchemaDatasetSet([], { instanceId: "1", databaseName: "two", schemaName: "three" });
            this.view.render();
        });

        it("should not display the browse more message", function() {
            expect(this.view.$(".browse_more")).not.toExist();
        });

        context("after the collection is loaded and there's a workspace'", function() {
            beforeEach(function() {
                this.view.collection.attributes.workspaceId = "1";
                this.view.collection.loaded = true;
                this.view.render();
            });

            it("renders the no datasets in this workspace message", function() {
                expect($(this.view.el)).toContainTranslation("dataset.browse_more_workspace", {linkText: "browse your data sources"});
                expect(this.view.$(".browse_more a")).toHaveHref("#/data_sources");
            });
        });

        context("when it is a DatasetSet and a name filter is applied", function() {
            beforeEach(function() {
                this.view.collection = new chorus.collections.WorkspaceDatasetSet();
                this.view.collection.loaded = true;
                this.view.collection.attributes.namePattern = "Liger";
                this.view.render();
            });

            it("renders the no datasets message if there are no datasets", function() {
                expect($(this.view.el)).toContainTranslation("dataset.filtered_empty");
            });
        });

        context("when there is no workspace", function() {
            beforeEach(function() {
                this.view.collection = new chorus.collections.SchemaDatasetSet([], { instanceId: "1", databaseName: "two", schemaName: "three" });
                this.view.collection.loaded = true;
                this.view.render();
            });

            it('renders the no datasets in the this data source message', function() {
                expect($(this.view.el)).toContainTranslation("dataset.browse_more_instance");
            });
        });
    });

    it("passes the 'activeWorkspace' option to the dataset views, so that they render the links", function() {
        expect(this.view.$("li a.image").length).toBe(this.collection.length);
        expect(this.view.$("li a.name").length).toBe(this.collection.length);

        this.view = new chorus.views.DatasetList({ collection: this.collection, activeWorkspace: false });
        this.view.render();

        expect(this.view.$("li a.image").length).toBe(0);
        expect(this.view.$("li a.name").length).toBe(0);
    });
});
