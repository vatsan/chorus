chorus.dialogs.ChangePassword = chorus.dialogs.Base.extend({
    templateName:"change_password",
    title:t("user.change_password.title"),
    additionalClass: "dialog-narrow",
    events:{
        "submit form":"save"
    },
    persistent:true,

    save:function (e) {
        e.preventDefault();

        this.bindings.add(this.model, "saved", this.saved);
        this.model.save({
            password:this.$("input[name=password]").val(),
            passwordConfirmation:this.$("input[name=passwordConfirmation]").val()
        });
    },

    saved:function () {
        $(document).trigger("close.facebox");
    }
});
