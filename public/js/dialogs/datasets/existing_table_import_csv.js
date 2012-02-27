chorus.dialogs.ExistingTableImportCSV = chorus.dialogs.Base.extend({
    className: "existing_table_import_csv",
    additionalClass: "table_import_csv",
    title: t("dataset.import.table.title"),
    delimiter: ',',

    events: {
        "click button.submit": "startImport",
        "change #include_header": "refreshCSV",
        "keyup input.delimiter[name=custom_delimiter]": "setOtherDelimiter",
        "paste input.delimiter[name=custom_delimiter]": "setOtherDelimiter",
        "click input.delimiter[type=radio]": "setDelimiter",
        "click input#delimiter_other": "focusOtherInputField"
    },

    setup: function() {
        this.resource = this.csv = this.options.csv;
        this.tableName = this.csv.get("toTable");
        chorus.PageEvents.subscribe("choice:setType", this.onSelectType, this);
        this.dataset = new chorus.models.Dataset({ workspace: {id: this.csv.get("workspaceId")}, id: this.options.datasetId })
        this.requiredResources.add(this.dataset);
        this.dataset.fetch();
    },

    postRender: function() {
        this.$(".tbody").unbind("scroll.follow_header");
        this.$(".tbody").bind("scroll.follow_header", _.bind(this.adjustHeaderPosition, this));
        this.setupScrolling(this.$(".tbody"));

        var self = this
        _.each(this.$(".column_mapping .map"), function(map) {
            var content = $("<ul></ul>");
            _.each(self.dataset.get("columnNames"), function(column) {
                content.append($("<li>").append($('<a class="name" href="#">' + column.name + '</a>')));
            });
            chorus.menu($(map), {
                content: content,
                style: {classes: "tooltip-on-modal"},
                contentEvents: {
                    'a.name': self.columnSelected
                }
            });
        })

        self.$("input.delimiter").removeAttr("checked");
        if (_.contains([",", "\t", ";", " "], self.delimiter)) {
            self.$("input.delimiter[value='" + self.delimiter + "']").attr("checked", "true");
        } else {
            self.$("input#delimiter_other").attr("checked", "true");
        }
    },

    columnSelected: function(e, api) {
        e.preventDefault();
        api.elements.target.find("a").text($(e.target).text());


    },

    additionalContext: function() {
        return {
            columns: this.csv.columnOrientedData(),
            delimiter: this.other_delimiter ? this.delimiter : '',
            directions: t("dataset.import.table.existing.directions", {
                toTable: this.csv.get("toTable")
            })
        }
    },

    startImport: function() {
        this.$('button.submit').startLoading("dataset.import.importing");
        var $names = this.$(".column_names input:text");
        var $types = this.$(".data_types .chosen");

        var columnData = _.map($names, function(name, i) {
            return {
                columnName: chorus.Mixins.dbHelpers.safePGName($(name).val()),
                columnType: $types.eq(i).text(),
                columnOrder: i + 1
            }
        })
        this.csv.set({
            delimiter: this.delimiter,
            columnsDef: JSON.stringify(columnData)
        })

        this.csv.bindOnce("saved", function() {
            this.closeModal();
            chorus.toast("dataset.import.started");
            chorus.PageEvents.broadcast("csv_import:started");
        }, this);

        this.csv.bindOnce("saveFailed", function() {
            this.$("button.submit").stopLoading();
        }, this);

        this.$("button.submit").startLoading("dataset.import.importing");

        this.csv.save();
    },

    refreshCSV: function() {
        this.csv.set({include_header: !!(this.$("#include_header").attr("checked")), delimiter: this.delimiter});
        this.render();
        this.recalculateScrolling();
    },

    adjustHeaderPosition: function() {
        this.$(".thead").css({ "left": -this.scrollLeft() });
    },

    scrollLeft: function() {
        var api = this.$(".tbody").data("jsp");
        return api && api.getContentPositionX();
    },

    setDelimiter: function(e) {
        if (e.target.value == "other") {
            this.delimiter = this.$("input[name=custom_delimiter]").val();
            this.other_delimiter = true;
        } else {
            this.delimiter = e.target.value;
            this.other_delimiter = false;
        }
        this.refreshCSV();
    },

    focusOtherInputField: function(e) {
        this.$("input[name=custom_delimiter]").focus();
    },

    setOtherDelimiter: function() {
        this.$("input.delimiter[type=radio]").removeAttr("checked");
        var otherRadio = this.$("input#delimiter_other");
        otherRadio.attr("checked", true)
        otherRadio.click();
    }
});