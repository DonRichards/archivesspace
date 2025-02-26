# Schema inherits from the abstract_archival_object schema, and must only include extensions/overrides unique to archival object records.

{
  :schema => {
    "$schema" => "http://www.archivesspace.org/archivesspace.json",
    "version" => 1,
    "type" => "object",
    "parent" => "abstract_archival_object",
    "uri" => "/repositories/:repo_id/archival_objects",
    "properties" => {
      "ref_id" => {"type" => "string", "maxLength" => 255, "pattern" => "\\A[a-zA-Z0-9\\-_:\\.]*\\z"},
      "component_id" => {"type" => "string", "maxLength" => 255, "required" => false, "default" => ""},

      "level" => {"type" => "string", "ifmissing" => "error", "dynamic_enum" => "archival_record_level"},
      "other_level" => {"type" => "string", "maxLength" => 255},
      "external_ark_url" => {"type" => "string", "required" => false},

      "import_current_ark" => {"type" => "string"},

      "import_previous_arks" => {
        "type" => "array",
        "items" => {
          "type" => "string",
        }
      },

      "title" => {"type" => "string", "maxLength" => 8192, "ifmissing" => nil},

      "slug" => {"type" => "string"},
      "is_slug_auto" => {"type" => "boolean", "default" => true},

      "display_string" => {"type" => "string", "maxLength" => 8192, "readonly" => true},

      "restrictions_apply" => {"type" => "boolean", "default" => false},
      "repository_processing_note" => {"type" => "string", "maxLength" => 65000},

      "parent" => {
        "type" => "object",
        "subtype" => "ref",
        "properties" => {
          "ref" => {"type" => "JSONModel(:archival_object) uri"},
          "_resolved" => {
            "type" => "object",
            "readonly" => "true"
          }
        }
      },

      "resource" => {
        "type" => "object",
        "subtype" => "ref",
        "properties" => {
          "ref" => {"type" => "JSONModel(:resource) uri"},
          "_resolved" => {
            "type" => "object",
            "readonly" => "true"
          }
        },
        "ifmissing" => "error"
      },

      "ancestors" => {
        "type" => "array",
        "items" => {
          "type" => "object",
          "subtype" => "ref",
          "properties" => {
            "ref" => {"type" => [{"type" => "JSONModel(:resource) uri"},
                                 {"type" => "JSONModel(:archival_object) uri"}]},
            "level" => {"type" => "string", "maxLength" => 255},
            "_resolved" => {
              "type" => "object",
              "readonly" => "true"
            }
          }
        }
      },

      "series" => {
        "type" => "object",
        "subtype" => "ref",
        "properties" => {
          "ref" => {"type" => "JSONModel(:archival_object) uri"},
          "_resolved" => {
            "type" => "object",
            "readonly" => "true"
          }
        }
      },

      "position" => {"type" => "integer", "required" => false},

      "instances" => {"type" => "array", "items" => {"type" => "JSONModel(:instance) object"}},

      "notes" => {
        "type" => "array",
        "items" => {"type" => [{"type" => "JSONModel(:note_bibliography) object"},
                               {"type" => "JSONModel(:note_index) object"},
                               {"type" => "JSONModel(:note_multipart) object"},
                               {"type" => "JSONModel(:note_singlepart) object"}]},
      },

      "has_unpublished_ancestor" => {"type" => "boolean", "readonly" => "true"},

      "representative_image" => {
        "type" => "JSONModel(:file_version) object",
        "readonly" => true
      },
      "ark_name" => {
        "type" => "JSONModel(:ark_name) object",
        "readonly" => true,
        "required" => false
      }

    },
  },
}
