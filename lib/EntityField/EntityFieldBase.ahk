class EntityFieldBase {
    fieldTypeId := ""
    container := ""
    eventMgr := ""
    defaultValue := ""
    entityObj := ""
    fieldKey := ""
    fieldDefinition := ""
    dataObj := ""
    userLayer := "data"
    multiple := false
    needsEntityRefresh := false

    static VALUE_TYPE_DATA := "data"
    static VALUE_TYPE_DEFAULT := "default"

    Definition {
        get => this.fieldDefinition
        set => this.fieldDefinition := value
    }

    IsMultiple {
        get => this.multiple
    }

    __New(fieldTypeId, entityObj, container, eventMgr, dataObj, fieldKey, fieldDefinition) {
        this.fieldTypeId := fieldTypeId
        this.eventMgr := eventMgr
        this.entityObj := entityObj
        this.container := container
        this.dataObj := dataObj
        this.fieldKey := fieldKey
        this.Definition := ParameterBag(this.DefinitionDefaults(fieldDefinition))
        this.Definition.Add(fieldDefinition)
        this.multiple := (this.Definition["cardinality"] == 0 || this.Definition["cardinality"] > 1)

        if (this.multiple && this.Definition["default"] && !HasBase(this.Definition["default"], Array.Prototype)) {
            this.Definition["default"] := [this.Definition["default"]]
        }
    }

    static Create(container, entityTypeId, entityObj, dataObj, fieldId, definition) {
        className := this.Prototype.__Class

        return %className%(
            definition["type"],
            entityObj,
            container,
            container.Get("manager.event"),
            dataObj,
            fieldId,
            definition
        )
    }

    DefaultCallbacks(valueType) {
        getCallback := ""
        setCallback := ""
        hasCallback := ""
        hasOverrideCallback := ""
        isEmptyCallback := ""
        deleteCallback := ""

        if (valueType == EntityFieldBase.VALUE_TYPE_DATA) {
            getCallback := ObjBindMethod(this, "_getDataValue", "*")
            setCallback := ObjBindMethod(this, "_setDataValue")
            hasCallback := ObjBindMethod(this, "_hasDataValue", "*", true)
            hasOverrideCallback := ObjBindMethod(this, "_hasDataValue", "", true)
            isEmptyCallback := ObjBindMethod(this, "_hasDataValue", "*", false, true)
            deleteCallback := ObjBindMethod(this, "_deleteDataValue")
        } else if (valueType == EntityFieldBase.VALUE_TYPE_DEFAULT) {
            getCallback := ObjBindMethod(this, "_getDefaultValue")
            setCallback := ObjBindMethod(this, "_emptySet")
            hasCallback := ObjBindMethod(this, "_hasDefaultValue", true)
            hasOverrideCallback := ObjBindMethod(this, "_hasDefaultOverride")
            isEmptyCallback := ObjBindMethod(this, "_hasDefaultValue", false, true)
            deleteCallback := ObjBindMethod(this, "_emptyDelete")
        }

        return Map(
            "GetValue", getCallback,
            "SetValue", setCallback,
            "HasValue", hasCallback,
            "HasOverride", hasOverrideCallback,
            "IsEmpty", isEmptyCallback,
            "DeleteValue", deleteCallback
        )
    }

    DefinitionDefaults(fieldDefinition) {
        valueType := fieldDefinition.Has("valueType") ? fieldDefinition["valueType"] : ""

        if (!valueType) {
            valueType := EntityFieldBase.VALUE_TYPE_DATA
        }

        return Map(
            "callbacks", this.DefaultCallbacks(valueType),
            "valueType", valueType,
            "dataLayer", this.userLayer,
            "default", this.defaultValue,
            "description", "",
            "editable", true,
            "formField", true,
            "group", "general",
            "help", "",
            "cardinality", 1,
            "modes", Map(),
            "processValue", false,
            "refreshEntityOnChange", false,
            "required", false,
            "storageKey", this.fieldKey,
            "title", this._generateTitle(),
            "type", this.fieldTypeId,
            "unique", false,
            "validators", [],
            "weight", 0,
            "widget", "text"
        )
    }

    GetDefinition(formMode := "") {
        definition := this.fieldDefinition

        if (formMode && definition && definition.Has("modes") && definition["modes"].Has(formMode)) {
            definition := List.Clone(definition, true).Add(definition["modes"][formMode])
        }

        return definition
    }

    _callback(name, params*) {
        callbackName := "callbacks." . name
        result := ""

        if (this.Definition[callbackName]) {
            if (!HasMethod(this.Definition[callbackName])) {
                throw EntityException("Callback " . name . " is not callable.")
            }

            result := this.Definition[callbackName](params*)
        }

        return result
    }

    GetValue(index := "") {
        return this.GetRawValue(index)
    }

    GetRawValue(index := "") {
        value := this._callback("GetValue")

        if (this.multiple && !HasBase(value, Array.Prototype)) {
            value := [value]
        }

        if (this.multiple && index && !value.Has(index)) {
            throw AppException("Index " . index . " does not exist in field " . this.fieldKey . ".")
        }

        if (this.multiple && index) {
            value := value[index]
        }

        return value
    }

    SetValue(value, index := "") {
        if (index && this.multiple) {
            existingValues := this.GetRawValue()

            if (existingValues.Length < (index + 1)) {
                throw AppException("Index to set is too high, there are only " . existingValues.Length . " values in field " . this.fieldKey . ".")
            }

            if (existingValues.Length < index) {
                existingValues.Push(value)
            } else {
                existingValues[index] := value
            }

            value := existingValues
        }

        if (this.multiple && !HasBase(value, Array.Prototype)) {
            value := [value]
        }

        this._callback("SetValue", value)
        this.RefreshEntity()
        return this
    }

    HasValue() {
        return this._callback("HasValue")
    }

    HasOverride() {
        return this._callback("HasOverride")
    }

    IsEmpty() {
        return this._callback("IsEmpty")
    }

    DeleteValue() {
        this._callback("DeleteValue")
        return this
    }

    ProcessFormInput(value) {
        this.SetValue(value)
    }

    Validate(value) {
        if (!HasBase(value, Array.Prototype)) {
            value := [value]
        }

        results := []

        validator := this.CreateValidator(this.GetValidators(value))

        for index, singleValue in value {
            results.Push(validator.Validate(singleValue))
        }

        return this.multiple ? results : results[1]
    }

    /**
     * "*" - All layers
     * "" - Default layer
     */
    _parseLayer(layer := "", allowAll := true) {
        if (!layer) {
            layer := this.Definition["dataLayer"]
        } else if (layer == "*" && !allowAll) {
            throw EntityException("Cannot pass wildcard for this layer value.")
        } else if (layer == "*") {
            layer := ""
        }

        return layer
    }

    _getDataValue(layer := "*") {
        return this.dataObj.GetValue(
            this.Definition["storageKey"],
            this.Definition["processValue"],
            this._parseLayer(layer),
            this.Definition["default"]
        )
    }

    _getDefaultValue() {
        return this.Definition["default"]
    }

    _setDataValue(value, layer := "") {
        this.dataObj.SetValue(
            this.Definition["storageKey"],
            value,
            this._parseLayer(layer, false)
        )

        if (this.Definition["refreshEntityOnChange"]) {
            this.needsEntityRefresh := true
        }
    }

    _emptySet(value) {

    }

    _hasDataValue(layer := "*", allowEmpty := true, negate := false) {
        val := this.dataObj.HasValue(
            this.Definition["storageKey"],
            this._parseLayer(layer),
            allowEmpty
        )

        if (this.multiple && HasBase(val, Array.Prototype)) {
            if (val.Length) {
                val := (val[1] != "")
            } else {
                val := false
            }
        }

        if (negate) {
            val := !val
        }

        return val
    }

    _hasDefaultValue(allowEmpty := true, negate := false) {
        hasValue := allowEmpty ? true : !!(this.Definition["default"])

        if (hasValue && !allowEmpty && this.multiple && HasBase(this.Definition["default"], Array.Prototype)) {
            hasValue := !!(this.Definition["default"][1])
        }

        if (negate) {
            hasValue := !hasValue
        }

        return hasValue
    }

    _hasDefaultOverride() {
        return false
    }

    _deleteDataValue(layer := "") {
        this.dataObj.DeleteValue(
            this.Definition["storageKey"],
            this._parseLayer(layer, false)
        )
    }

    _emptyDelete() {

    }

    RefreshEntity(force := false, refreshUserData := false) {
        if (force || this.needsEntityRefresh) {
            this.entityObj.RefreshEntityData(true, refreshUserData)
            this.needsEntityRefresh := false
        }
    }

    GetValidators(value) {
        validators := []

        if (this.Definition["required"]) {
            validators.Push(Map(
                "condition", "IsEmptyCondition",
                "args", ["", true]
            ))
        }

        if (this.Definition["validators"]) {
            additional := this.Definition["validators"]

            if (!HasBase(additional, Array.Prototype)) {
                additional := [additional]
            }

            validators.Push(additional*)
        }

        if (this.Definition["unique"]) {
            ; @todo Check other entities to ensure this value isn't already used
        }

        return validators
    }

    _generateTitle() {
        title := this.fieldKey
        title := RegexReplace(title, "[^A-Z\s]\K([A-Z])", " $1")
        return StrTitle(title)
    }

    GetTitle() {
        return this.Definition["title"]
    }

    CreateValidator(conditionDefs, negate := false) {
        if (!HasBase(conditionDefs, Array.Prototype)) {
            conditionDefs := [conditionDefs]
        }

        conditions := []

        for conditionDef in conditionDefs {
            if (HasBase(conditionDef, ConditionBase.Prototype)) {
                conditions.Push(conditionDef)
            } else if (Type(conditionDef) == "String") {
                if (HasMethod(%conditionDef%)) {
                    conditions.Push(%conditionDef%())
                } else {
                    throw EntityException("Class " . conditionDef . " is uncallable.")
                }
            } else if (HasBase(conditionDef, Map.Prototype)) {
                if (conditionDef.Has("condition")) {
                    className := conditionDef["condition"]

                    if (HasMethod(%className%)) {
                        args := conditionDef.Has("args") ? conditionDef["args"] : []
                        conditions.Push(%className%(args*))
                    } else {
                        throw EntityException("Class " . className . " is uncallable.")
                    }
                } else {
                    throw EntityException("Validator conditiond definition is missing the condition property.")
                }
            }
        }

        return BasicValidator(conditions, negate)
    }
}
