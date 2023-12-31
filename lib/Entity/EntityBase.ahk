class EntityBase {
    idVal := ""
    entityTypeIdVal := ""
    parentEntityObj := ""
    parentEntityTypeId := ""
    parentEntityId := ""
    parentEntityStorage := false
    container := ""
    app := ""
    eventMgr := ""
    dataObj := ""
    storageObj := ""
    idSanitizer := ""
    sanitizeId := true
    loading := false
    loaded := false
    dataLayer := "data"
    dataLoaded := false

    Id {
        get => this.GetId()
        set => this.SetId(value)
    }

    EntityTypeId {
        get => this.entityTypeIdVal
        set => this.entityTypeIdVal := value
    }

    EntityType {
        get => this.GetEntityType()
        set => this.EntityTypeId := value
    }

    FieldData {
        get => this.GetData().GetMergedData()
    }

    Name {
        get => this.GetValue("name")
        set => this.SetValue("name", value)
    }

    RawData {
        get => this.GetData().GetLayer(this.dataLayer)
        set => this.GetData().SetLayer(this.dataLayer, value)
    }

    ParentEntity {
        get => this.GetParentEntity()
    }

    ReferencedEntities {
        get => this.GetReferencedEntities(false)
    }

    ChildEntities {
        get => this.GetReferencedEntities(true)
    }

    ChildEntityData {
        get => this.GetAllChildEntityData()
    }

    __Item[key := ""] {
        get => this.GetValue(key)
        set => this.SetValue(key, value)
    }

    __Enum(numberOfVars) {
        return this.GetAllValues().__Enum(numberOfVars)
    }

    __New(id, entityTypeId, container, eventMgr, storageObj, idSanitizer := "", autoLoad := true, parentEntity := "", parentEntityStorage := false) {
        this.app := container.GetApp()
        this.idSanitizer := idSanitizer

        if (this.sanitizeId && this.idSanitizer) {
            idVal := this.idSanitizer.Process(id)
        }

        this.idVal := id
        this.entityTypeIdVal := entityTypeId
        this.container := container
        this.eventMgr := eventMgr
        this.storageObj := storageObj
        this.parentEntityStorage := parentEntityStorage

        if (!parentEntity && this.parentEntityObj) {
            parentEntity := this.parentEntityObj
        }

        this.DiscoverParentEntity(container, eventMgr, id, storageObj, idSanitizer, parentEntity)

        this._createEntityData()
        this.SetupEntity()

        if (autoLoad) {
            this.LoadEntity()
        }
    }

    static Create(container, eventMgr, id, entityTypeId, storageObj, idSanitizer, autoLoad := true, parentEntity := "", parentEntityStorage := false) {
        className := this.Prototype.__Class

        return %className%(
            id,
            entityTypeId,
            container,
            eventMgr,
            storageObj,
            idSanitizer,
            autoLoad,
            parentEntity,
            parentEntityStorage
        )
    }

    _createEntityData() {
        if (!this.dataLoaded) {
            this.dataObj := EntityData(this, this._getLayerNames(), this._getLayerSources())
        }

        this.dataLoaded := true
    }

    _getLayerNames() {
        ; "auto" and "data" are automatically added at the end of the array later.
        return ["defaults"]
    }

    _getLayerSources() {
        layerSource := this.parentEntityStorage
            ? ParentEntityLayerSource(this)
            : EntityStorageLayerSource(this.storageObj, this.GetStorageId())

        return Map(
            "defaults", ObjBindMethod(this, "InitializeDefaults"),
            "auto", ObjBindMethod(this, "AutoDetectValues"),
            "data", layerSource
        )
    }

    /**
     * Get an array of all IDs
     *
     * List managed IDs and give modules a chance to add others.
     */
    ListEntities(includeManaged := true, includeExtended := true) {
        return this.container["entity_manager." . this.EntityTypeId]
            .ListEntities(includeManaged, includeExtended)
    }

    DiscoverParentEntity(container, eventMgr, id, storageObj, idSanitizer, parentEntity := "") {
        event := EntityParentEvent(EntityEvents.ENTITY_DISCOVER_PARENT, this.entityTypeId, this, parentEntity)
        this.eventMgr.DispatchEvent(event)

        if (event.ParentEntity) {
            this.parentEntityObj := event.ParentEntity
        } else if (event.ParentEntityId) {
            this.parentEntityTypeId := event.ParentEntityTypeId
            this.parentEntityId := event.ParentEntityId
            this.parentEntityMgr := event.ParentEntityManager
                ? event.ParentEntityManager
                : container.Get("entity_manager." . event.ParentEntityTypeId)

        }

        this.parentEntityObj := event.ParentEntity

        return event.ParentEntity
    }

    GetParentEntity() {
        return this.parentEntityObj
    }

    SetupEntity() {
        event := EntityEvent(EntityEvents.ENTITY_PREPARE, this.entityTypeId, this)
        this.eventMgr.DispatchEvent(event)
    }

    GetAllValues(raw := false) {
        return this.GetData().GetMergedData(!raw)
    }

    GetEntityType() {
        ; @todo Inject entity type manager service
        return this.container.Get("manager.entity_type")[this.EntityTypeId]
    }

    InitializeDefaults() {
        defaults := Map(
            "name", this.Id
        )

        return defaults
    }

    GetData() {
        return this.dataObj
    }

    GetValue(key) {
        if (key == "id") {
            return this.GetId()
        }

        return this.GetData().GetValue(key)
    }

    SetValue(key, value) {
        if (key == "id") {
            this.SetId(value)
        } else {
            this.GetData().SetValue(key, value)
        }
    }

    GetId() {
        return this.idVal
    }

    SetId(newId) {
        throw EntityException("Setting the ID is not supported by this entity.")
    }

    HasId(negate := false) {
        hasId := !!(this.GetId())

        return negate ? !hasId : hasId
    }

    Has(key, allowEmpty := true) {
        return this.GetData().HasValue(key, "", allowEmpty)
    }

    DeleteValue(key) {
        return this.GetData().DeleteValue(key, this.dataLayer)
    }

    CreateSnapshot(name, recurse := false) {
        if (recurse) {
            for index, entityObj in this.ChildEntities {
                entityObj.GetData().CreateSnapshot(name, recurse)
            }
        }

        this.GetData().CreateSnapshot(name)

        return this
    }

    RestoreSnapshot(name, recurse := false) {
        this.GetData().RestoreSnapshot(name)

        if (recurse) {
            for index, entityObj in this.ChildEntities {
                entityObj.GetData().RestoreSnapshot(name, recurse)
            }
        }

        return this
    }

    GetStorageId() {
        return this.Id
    }

    LoadEntity(reload := false, recurse := false) {
        if (this.loading) {
            throw AppException("Attempting to load entity with a circular reference.")
        }

        if (!this.loading && this.dataLoaded && (!this.loaded || reload)) {
            this.loading := true
            this.RefreshEntityData(recurse)
            this.CreateSnapshot("original")
            this.loaded := true
            loaded := true
            this.loading := false

            if (recurse) {
                for index, entityObj in this.ChildEntities {
                    entityObj.LoadEntity(reload, recurse)
                }
            }

            if (loaded) {
                event := EntityEvent(EntityEvents.ENTITY_LOADED, this.entityTypeId, this)
                this.eventMgr.DispatchEvent(event)
            }
        }
    }

    RefreshEntityData(recurse := true, reloadUserData := false) {
        this.GetData().UnloadAllLayers(reloadUserData)

        if (recurse) {
            for index, entityObj in this.ChildEntities {
                entityObj.RefreshEntityData(recurse, reloadUserData)
            }
        }

        event := EntityRefreshEvent(EntityEvents.ENTITY_REFRESH, this.entityTypeId, this, recurse)
        this.eventMgr.DispatchEvent(event)
    }

    AutoDetectValues() {
        values := Map()

        event := EntityDetectValuesEvent(EntityEvents.ENTITY_DETECT_VALUES, this.EntityTypeId, this, values)
        this.eventMgr.DispatchEvent(event)

        event := EntityDetectValuesEvent(EntityEvents.ENTITY_DETECT_VALUES_ALTER, this.EntityTypeId, this, event.Values)
        this.eventMgr.DispatchEvent(event)

        return event.Values
    }

    SaveEntity(recurse := true) {
        if (!this.dataObj) {
            return
        }

        alreadyExists := this.dataObj.HasData(true)

        event := EntityEvent(EntityEvents.ENTITY_PRESAVE, this.entityTypeId, this)
        this.eventMgr.DispatchEvent(event)

        if (recurse) {
            for index, entityObj in this.ChildEntities {
                entityObj.SaveEntity(recurse)
            }
        }

        this.GetData().SaveData()
        this.CreateSnapshot("original")

        if (alreadyExists) {
            event := EntityEvent(EntityEvents.ENTITY_UPDATED, this.entityTypeId, this)
            this.eventMgr.DispatchEvent(event)
        } else {
            event := EntityEvent(EntityEvents.ENTITY_CREATED, this.entityTypeId, this)
            this.eventMgr.DispatchEvent(event)
        }

        event := EntityEvent(EntityEvents.ENTITY_SAVED, this.entityTypeId, this)
        this.eventMgr.DispatchEvent(event)
    }

    RestoreEntity(snapshot := "original") {
        dataObj := this.GetData()
        if (dataObj.HasSnapshot(snapshot)) {
            dataObj.RestoreSnapshot(snapshot)

            event := EntityEvent(EntityEvents.ENTITY_RESTORED, this.entityTypeId, this)
            this.eventMgr.DispatchEvent(event)
        }
    }

    DeleteEntity(recurse := false) {
        if (this.storageObj.HasData(this.GetStorageId())) {
            event := EntityEvent(EntityEvents.ENTITY_PREDELETE, this.entityTypeId, this)
            this.eventMgr.DispatchEvent(event)

            if (recurse) {
                for index, entityObj in this.ChildEntities {
                    entityObj.DeleteEntity(recurse)
                }
            }

            this.storageObj.DeleteData(this.GetStorageId())

            event := EntityEvent(EntityEvents.ENTITY_DELETED, this.entityTypeId, this)
            this.eventMgr.DispatchEvent(event)
        }
    }

    Validate() {
        validateResult := Map("success", true, "invalidKeys", [])

        event := EntityValidateEvent(EntityEvents.ENTITY_VALIDATE, this.entityTypeId, this, validateResult)
        this.eventMgr.DispatchEvent(event)

        return event.ValidateResult
    }

    IsModified(recurse := false) {
        changes := this.DiffChanges(recurse)

        return !!(changes.GetAdded().Count || changes.GetModified().Count || changes.GetDeleted().Count)
    }

    DiffChanges(recurse := true) {
        diff := this.GetData().DiffChanges("original", this.dataLayer)

        if (recurse) {
            diffs := [diff]

            for index, referencedEntity in this.ChildEntities {
                diffs.Push(referencedEntity.DiffChanges(recurse))
            }

            diff := DiffResult.Combine(diffs)
        }

        return diff
    }

    GetReferencedEntities(onlyChildren := false) {
        return []
    }

    Edit(mode := "config", owner := "") {
        this.LoadEntity()
        editMode := mode == "child" ? "config" : mode
        result := this.LaunchEditWindow(editMode, owner)
        fullDiff := ""

        if (result == "Cancel" || result == "Skip") {
            this.RestoreEntity()
        } else {
            fullDiff := this.DiffChanges(true)

            if (mode == "config" && fullDiff.HasChanges()) {
                this.SaveEntity()
            }
        }

        if (!fullDiff) {
            fullDiff := DiffResult(Map(), Map(), Map())
        }

        return fullDiff
    }

    LaunchEditWindow(mode, ownerOrParent := "") {
        result := "Cancel"

        while (mode) {
            result := this.app["manager.gui"].Dialog(Map(
                "type", "SimpleEntityEditor",
                "mode", mode,
                "child", !!(ownerOrParent),
                "ownerOrParent", ownerOrParent
            ), this)

            reloadPrefix := "mode:"

            if (result == "Simple") {
                mode := "simple"
            } else if (result == "Advanced") {
                mode := "config"
            } else if (result && InStr(result, reloadPrefix) == 1) {
                mode := SubStr(result, StrLen(reloadPrefix) + 1)
            } else {
                mode := ""
            }
        }

        return result
    }

    RevertToDefault(key) {
        this.GetData().DeleteUserValue(key)
    }

    GetEditorButtons(mode) {
        return (mode == "build")
            ? "*&Continue|&Skip"
            : "*&Save|&Cancel"
    }

    GetEditorDescription(mode) {
        text := ""

        if (mode == "config") {
            text := "The details entered here will be saved and used for all future builds."
        } else if (mode == "build") {
            text := "The details entered here will be used for this build only."
        }

        return text
    }

    UpdateDefaults(recurse := false) {
        if (recurse) {
            for key, child in this.ChildEntities {
                child.UpdateDefaults(recurse)
            }
        }

        this.GetData().UnloadAllLayers(false)
    }

    GetAllChildEntityData() {
        return this.GetData().GetExtraData()
    }

    GetChildEntityData(entityTypeId, entityId) {
        dataKey := entityTypeId . "." . entityId

        childData := this.GetData().GetExtraData(dataKey)

        return childData ? childData : Map()
    }

    SetChildEntityData(entityTypeId, entityId, data) {
        dataKey := entityTypeId . "." . entityId

        if (!data) {
            data := Map()
        }

        this.GetData().SetExtraData(data, dataKey)

        return this
    }

    HasChildEntityData(entityTypeId, entityId) {
        dataKey := entityTypeId . "." . entityId

        return this.GetData().HasExtraData(dataKey)
    }

    DeleteChildEntityData(entityTypeId, entityId) {
        dataKey := entityTypeId . "." . entityId

        this.GetData().DeleteExtraData(dataKey)

        return this
    }
}
