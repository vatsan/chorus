chorus.pages.UserShowPage = chorus.pages.Base.extend({
    helpId: "user",

    setup: function(userId) {
        this.model = new chorus.models.User({id: userId});
        this.model.fetch();

        this.handleFetchErrorsFor(this.model);

        this.mainContent = new chorus.views.MainContentView({
            model: this.model,
            content: new chorus.views.UserShow({model: this.model}),
            contentHeader: new chorus.views.DisplayNameHeader({ model: this.model, showTagBox: true }),
            contentDetails: new chorus.views.StaticTemplate("plain_text", {text: t("users.details")})
        });

        if(this.model.id === chorus.session.user().id.toString()){
            this.sidebar = new chorus.views.UserSidebar({model: this.model, showApiKey: true});
        } else {
            this.sidebar = new chorus.views.UserSidebar({model: this.model});
        }

        this.listenTo(this.model, "loaded", this.render);
        this.breadcrumbs.requiredResources.add(this.model);

    },

    crumbs: function() {
        return [
            { label: t("breadcrumbs.home"), url: "#/" },
            { label: t("breadcrumbs.users"), url: "#/users" },
            { label: this.model.loaded ? this.model.displayShortName(20) : "..." }
        ];
    }
});
