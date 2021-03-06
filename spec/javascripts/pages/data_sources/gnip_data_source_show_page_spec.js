describe("chorus.pages.GnipDataSourceShowPage", function() {
    beforeEach(function() {
        this.model = rspecFixtures.gnipDataSource({name: "gnip"});
        this.page = new chorus.pages.GnipDataSourceShowPage(this.model.id);
    });

    context('after the data source has loaded successfully', function() {
        beforeEach(function() {
            this.server.completeFetchFor(this.model);
            this.page.render();
        });

        it("displays the breadcrumbs", function() {
            expect(this.page.$(".breadcrumb:eq(0) a").attr("href")).toBe("#/");
            expect(this.page.$(".breadcrumb:eq(0)").text().trim()).toBe(t("breadcrumbs.home"));

            expect(this.page.$(".breadcrumb:eq(1) a").attr("href")).toBe("#/data_sources");
            expect(this.page.$(".breadcrumb:eq(1)").text().trim()).toBe(t("breadcrumbs.instances"));

            expect(this.page.$(".breadcrumb:eq(2)").text().trim()).toBe("gnip");
        });

        it("has a title bar with an icon", function() {
            expect(this.page.$(".content_header")).toContainText("gnip");
            expect(this.page.$(".content_header img").attr("src")).toContain("/images/data_sources/icon_gnip_data_source.png");
        });

        it("has a tag box", function() {
            expect(this.page.$('.tag_box')).toExist();
        });

        it("displays the sidebar", function() {
            var sidebar = this.page.sidebar;
            expect(sidebar).toBeDefined();
            expect(sidebar).toBeA(chorus.views.InstanceListSidebar);
            expect(sidebar.model.id).toBe(this.model.id);
            expect(this.page.$('.sidebar_content')).toContainText('Import Stream');
        });

    });
});